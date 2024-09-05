import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class VideoCallScreen extends StatefulWidget {
  final List<String> selectedFriendIds;

  VideoCallScreen({required this.selectedFriendIds});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  late IO.Socket _socket;
  String roomId = "";
  bool _videoEnabled = true;
  bool _audioEnabled = true;
  late MediaStream _localStream;

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
    _initializeSocket();
    _initializeRenderer();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _peerConnections.values.forEach((pc) => pc.close());
    _socket.disconnect();
    super.dispose();
  }

  void _initializeSocket() {
    _socket = IO.io('http://your-server-url',
        IO.OptionBuilder().setTransports(['websocket']).build());

    _socket.on('connect', (_) {
      _socket.emit('join', roomId);
    });

    _socket.on('existing_clients', (clients) {
      clients.forEach((clientId) async {
        await _createPeerConnection(clientId);
        final offer = await _peerConnections[clientId]!.createOffer();
        await _peerConnections[clientId]!.setLocalDescription(offer);
        _socket
            .emit('webrtc_offer', {'sdp': offer.toMap(), 'targetId': clientId});
      });
    });

    _socket.on('new_client', (clientId) async {
      await _createPeerConnection(clientId);
    });

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

    _socket.on('webrtc_answer', (data) async {
      final senderId = data['senderId'];
      await _peerConnections[senderId]!.setRemoteDescription(
          RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']));
    });

    _socket.on('webrtc_ice_candidate', (data) async {
      final senderId = data['senderId'];
      final candidate = RTCIceCandidate(data['candidate']['candidate'],
          data['candidate']['sdpMid'], data['candidate']['sdpMLineIndex']);
      //await _peerConnections[senderId]!.onIceCandidate(candidate);
    });

    _socket.on('chat_message', (data) {
      // Handle incoming chat messages
    });
  }

  Future<void> _initializeRenderer() async {
    await _localRenderer.initialize();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': _audioEnabled,
        'video': _videoEnabled ? {'width': 1280, 'height': 720} : false
      });
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      print('Error accessing local stream: $e');
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

  void _toggleVideo() {
    setState(() {
      _videoEnabled = !_videoEnabled;
      _localStream.getVideoTracks().forEach((track) {
        track.enabled = _videoEnabled;
      });
    });
  }

  void _toggleAudio() {
    setState(() {
      _audioEnabled = !_audioEnabled;
      _localStream.getAudioTracks().forEach((track) {
        track.enabled = _audioEnabled;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Call')),
      body: Column(
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
                      final clientId = _remoteRenderers.keys.elementAt(index);
                      return RTCVideoView(_remoteRenderers[clientId]!);
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: Icon(Icons.video_call), onPressed: _toggleVideo),
              IconButton(icon: Icon(Icons.mic), onPressed: _toggleAudio),
            ],
          ),
        ],
      ),
    );
  }
}
