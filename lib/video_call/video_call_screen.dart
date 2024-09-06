import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/animation.dart';
import '../../globals.dart';
import '../../socket_service.dart';

class VideoCallScreen extends StatefulWidget {
  final List<String> selectedFriendIds;

  VideoCallScreen({required this.selectedFriendIds});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  late IO.Socket _socket;
  String roomId = "";
  bool _videoEnabled = true;
  bool _audioEnabled = true;
  late MediaStream _localStream;

  final List<Map<String, String>> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();

  late AnimationController _chatAnimationController;
  late Animation<Offset> _chatOffsetAnimation;
  bool _isChatVisible = false;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _socket = SocketService().socket!;
    _initializeSocket();
    _initializeRenderer();

    // 채팅 애니메이션 컨트롤러 설정
    _chatAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _chatOffsetAnimation = Tween<Offset>(
      begin: Offset(1.0, 0.0), // 화면의 오른쪽 밖에서 시작
      end: Offset(0.0, 0.0), // 화면 안으로 이동
    ).animate(CurvedAnimation(
      parent: _chatAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _disposeLocalStream();
    _localRenderer.dispose();
    _peerConnections.values.forEach((pc) => pc.close());
    _socket.disconnect();
    _chatAnimationController.dispose();
    super.dispose();
  }

  Future<void> _disposeLocalStream() async {
    _localStream.getTracks().forEach((track) {
      track.stop();
    });
    _localRenderer.srcObject = null;
  }

  void _initializeSocket() {
    // 기존 클라이언트 목록 받기
    _socket.on('existing_clients', (clients) {
      clients.forEach((clientId) async {
        await _createPeerConnection(clientId);
        final offer = await _peerConnections[clientId]!.createOffer();
        await _peerConnections[clientId]!.setLocalDescription(offer);
        _socket
            .emit('webrtc_offer', {'sdp': offer.toMap(), 'targetId': clientId});
      });
    });

    // 새로운 클라이언트 접속 처리
    _socket.on('new_client', (clientId) async {
      await _createPeerConnection(clientId);
    });

    // Offer 받기
    _socket.on('webrtc_offer', (data) async {
      final senderId = data['senderId'];
      if (!_peerConnections.containsKey(senderId)) {
        await _createPeerConnection(senderId);
      }
      await _peerConnections[senderId]!.setRemoteDescription(
          RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']));
      final answer = await _peerConnections[senderId]!.createAnswer();
      await _peerConnections[senderId]!.setLocalDescription(answer);
      _socket
          .emit('webrtc_answer', {'sdp': answer.toMap(), 'targetId': senderId});
    });

    // Answer 받기
    _socket.on('webrtc_answer', (data) async {
      final senderId = data['senderId'];
      await _peerConnections[senderId]!.setRemoteDescription(
          RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']));
    });

    // ICE Candidate 받기
    _socket.on('webrtc_ice_candidate', (data) async {
      final senderId = data['senderId'];
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      await _peerConnections[senderId]!.addCandidate(candidate);
    });

    // 채팅 메시지 받기
    _socket.on('chat_message', (data) {
      if (data['sender'] != USER_ID) {
        _addMessageToChat(data['sender'], data['message']);
      }
    });
  }

  void _addMessageToChat(String sender, String message) {
    setState(() {
      _chatMessages.add({'sender': sender, 'message': message});
    });
  }

  Future<void> _initializeRenderer() async {
    await _localRenderer.initialize();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': _audioEnabled,
        'video': {
          'facingMode': 'user',
          'width': 1280,
          'height': 720,
        }
      });

      _localRenderer.srcObject = _localStream;

      setState(() {});
    } catch (e) {
      print('로컬 스트림 접근 에러: $e');
    }
  }

  Future<void> _createPeerConnection(String clientId) async {
    final pc = await createPeerConnection(_iceServers);
    _peerConnections[clientId] = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate != null) {
        _socket.emit('webrtc_ice_candidate', {
          'targetId': clientId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      }
    };

    pc.onTrack = (event) {
      if (!_remoteRenderers.containsKey(clientId)) {
        final renderer = RTCVideoRenderer();
        renderer.initialize().then((_) {
          renderer.srcObject = event.streams[0];
          setState(() {
            _remoteRenderers[clientId] = renderer;
          });
        });
      } else {
        _remoteRenderers[clientId]?.srcObject = event.streams[0];
      }
    };

    _localStream.getTracks().forEach((track) {
      pc.addTrack(track, _localStream);
    });
  }

  void _sendMessage() {
    if (_chatController.text.isNotEmpty) {
      _socket.emit('chat_message', {
        'sender': USER_ID,
        'message': _chatController.text,
      });
      _addMessageToChat(USER_ID, _chatController.text);
      _chatController.clear();
    }
  }

  void _toggleChatVisibility() {
    setState(() {
      _isChatVisible = !_isChatVisible;
      if (_isChatVisible) {
        _chatAnimationController.forward(); // 채팅창 나타나기
      } else {
        _chatAnimationController.reverse(); // 채팅창 사라지기
      }
    });
  }

  void _toggleVideo() async {
    setState(() {
      _videoEnabled = !_videoEnabled;
    });
    final videoTrack = _localStream.getVideoTracks().first;
    videoTrack.enabled = _videoEnabled;
  }

  void _toggleAudio() async {
    setState(() {
      _audioEnabled = !_audioEnabled;
    });
    final audioTrack = _localStream.getAudioTracks().first;
    audioTrack.enabled = _audioEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('비디오 통화'),
        actions: [
          IconButton(
            icon: Icon(_isChatVisible ? Icons.chat : Icons.chat_outlined),
            onPressed: _toggleChatVisibility, // 채팅창 토글 버튼
          ),
          IconButton(
            icon: Icon(_videoEnabled ? Icons.videocam : Icons.videocam_off),
            onPressed: _toggleVideo, // 비디오 토글 버튼
          ),
          IconButton(
            icon: Icon(_audioEnabled ? Icons.mic : Icons.mic_off),
            onPressed: _toggleAudio, // 오디오 토글 버튼
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (_localRenderer.srcObject != null)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          width: 120,
                          height: 160,
                          child: RTCVideoView(_localRenderer),
                        ),
                      ),
                    Positioned.fill(
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          childAspectRatio: 16 / 9,
                        ),
                        itemCount: _remoteRenderers.length,
                        itemBuilder: (context, index) {
                          final clientId =
                              _remoteRenderers.keys.elementAt(index);
                          return RTCVideoView(_remoteRenderers[clientId]!);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 채팅창 슬라이드 애니메이션
          AnimatedBuilder(
            animation: _chatAnimationController,
            builder: (context, child) {
              return FractionalTranslation(
                translation: _chatOffsetAnimation.value,
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.75, // 화면의 75% 너비
                height: double.infinity,
                color: Colors.grey[300],
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _chatMessages.length,
                        itemBuilder: (context, index) {
                          final message = _chatMessages[index];
                          return ListTile(
                            title: Text(message['sender']!),
                            subtitle: Text(message['message']!),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            decoration: InputDecoration(hintText: '메시지를 입력하세요'),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.send),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
