import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sticker_memo/socket_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../globals.dart';

class VideoCallScreen extends StatefulWidget {
  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  late WebViewController _webViewController; // WebViewController 선언
  late IO.Socket _socket;
  String roomId = '';

  @override
  void initState() {
    super.initState();
    _socket = SocketService().socket!;
    _initializeWebView();
  }

  void _initializeWebView() {
    _renderRoomNumber();
    _webViewController = WebViewController();

    // URLRequest에 헤더 추가
    _webViewController.loadRequest(
      Uri.parse(
          'https://vervet-sacred-needlessly.ngrok-free.app/roomId?roomId=$roomId'),
      // headers: {
      //   'ngrok-skip-browser-warning': '1', // ngrok 헤더 추가
      // },
    );

    _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    _webViewController.addJavaScriptChannel(
      'Flutter',
      onMessageReceived: (JavaScriptMessage message) {
        // JavaScript에서 전달된 메시지를 Flutter에서 처리
        print(message.message);
      },
    );

    if (_webViewController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_webViewController.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _inviteFriendsForVideoCall(
      List<String> selectedFriendIds, String roomId) {
    final data = {
      'inviterId': USER_ID, // 현재 사용자 ID
      'inviterName': USER_NAME, // 현재 사용자 이름
      'friendIds': selectedFriendIds, // 초대할 친구들의 ID 리스트
      'roomId': roomId, // 화상 통화 방 ID
    };

    // 소켓을 통해 친구들에게 초대 요청 전송
    _socket.emit('invite_friends', data);
  }

  // 방 번호 렌더링 및 방 참여
  void _renderRoomNumber() {
    final random = Random();
    roomId = random.nextInt(10000000).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Conference'),
      ),
      body: SafeArea(
        child: WebViewWidget(controller: _webViewController),
      ),
    );
  }
}
