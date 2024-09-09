import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sticker_memo/socket_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;

import '../../globals.dart';

class VideoCallScreen extends StatefulWidget {
  final List<String> selectedFriendNames;

  VideoCallScreen({required this.selectedFriendNames});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  WebViewController? _webViewController; // WebViewController를 nullable로 설정
  late IO.Socket _socket;
  String roomId = '';

  @override
  void initState() {
    super.initState();
    _socket = SocketService().socket!;
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    _renderRoomNumber();
    await _shareUrlWithFriends();

    final webViewController = WebViewController();

    webViewController.loadRequest(
      Uri.parse(
          'https://vervet-sacred-needlessly.ngrok-free.app/roomId?roomId=$roomId'),
    );

    webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    webViewController.addJavaScriptChannel(
      'Flutter',
      onMessageReceived: (JavaScriptMessage message) {
        print(message.message);
      },
    );

    if (webViewController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (webViewController.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    // WebViewController를 상태에 설정
    setState(() {
      _webViewController = webViewController;
    });
  }

  Future<void> _shareUrlWithFriends() async {
    try {
      for (String friendUserName in widget.selectedFriendNames) {
        final url = Uri.parse('$SERVER_IP/invite');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'sourceUserName': USER_NAME,
            'targetUserName': friendUserName,
            'inviteUrl':
                'https://vervet-sacred-needlessly.ngrok-free.app/roomId?roomId=$roomId',
          }),
        );

        if (response.statusCode != 200) {
          print('링크 공유 실패: ${response.statusCode}');
          return;
        }
      }

      print('링크 공유 성공');
    } catch (e) {
      print('링크 공유 중 오류가 발생했습니다.');
    }
  }

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
        child: _webViewController == null
            ? Center(
                child:
                    CircularProgressIndicator()) // WebViewController 초기화 전 로딩 스피너 표시
            : WebViewWidget(controller: _webViewController!),
      ),
    );
  }
}
