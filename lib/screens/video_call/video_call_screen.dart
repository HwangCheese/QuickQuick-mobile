import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sticker_memo/socket_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';

import '../../../globals.dart';

class VideoCallScreen extends StatefulWidget {
  final List<String>? selectedFriendIds;
  final String? initialUrl;

  VideoCallScreen({this.selectedFriendIds, this.initialUrl});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  InAppWebViewController? _webViewController; // WebViewController를 nullable로 설정
  late IO.Socket _socket;
  String roomId = '';
  late PullToRefreshController pullToRefreshController;
  late ContextMenu contextMenu;
  late Uri uri;
  final GlobalKey webViewKey = GlobalKey();
  List<String>? selectedFriendIds;

  @override
  void initState() {
    super.initState();

    if (widget.initialUrl != null) {
      uri = Uri.parse(widget.initialUrl!);
    } else {
      _initializeWebView();
    }
  }

  Future<void> _initializeWebView() async {
    _renderRoomNumber();
    if (widget.selectedFriendIds != null) {
      selectedFriendIds = widget.selectedFriendIds;
      await _shareUrlWithFriends();
    }
  }

  Future<void> _shareUrlWithFriends() async {
    try {
      for (String friendUserId in selectedFriendIds!) {
        final url = Uri.parse('$SERVER_IP/invite');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'sourceUserName': USER_NAME,
            'targetUserId': friendUserId,
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
        child: InAppWebView(
          key: webViewKey,
          initialUrlRequest: URLRequest(
            url: WebUri(
                'https://vervet-sacred-needlessly.ngrok-free.app/roomId?roomId=$roomId'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowBackgroundAudioPlaying: true,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
          ),
          // shouldOverrideUrlLoading: (controller, navigationAction) async {
          //   var uri = navigationAction.request.url!;
          //
          //   if (![
          //     "http",
          //     "https",
          //     "file",
          //     "chrome",
          //     "data",
          //     "javascript",
          //     "about"
          //   ].contains(uri.scheme)) {
          //     if (await canLaunchUrl(uri)) {
          //       // Launch the App
          //       await launchUrl(
          //         uri,
          //       );
          //       // and cancel the request
          //       return NavigationActionPolicy.CANCEL;
          //     }
          //   }
          //
          //   return NavigationActionPolicy.ALLOW;
          // },
          onWebViewCreated: (InAppWebViewController controller) {
            setState(() {
              _webViewController = controller;
            });
          },
          onPermissionRequest:
              (InAppWebViewController controller, request) async {
            return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT);
          },
          onJsAlert: (controller, jsAlertRequest) async {
            print(jsAlertRequest);
            return JsAlertResponse(handledByClient: true);
          },
          onConsoleMessage: (controller, consoleMessage) {
            print(consoleMessage.message);
          },
        ),
      ),
    );
  }
}
