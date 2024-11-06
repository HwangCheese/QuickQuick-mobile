import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sticker_memo/socket_service.dart';
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
  //InAppWebViewController? _webViewController;
  late IO.Socket _socket;
  String roomId = '';
  // late PullToRefreshController pullToRefreshController;
  // late ContextMenu contextMenu;
  // WebUri? uri; // WebUri를 nullable로 설정
  final GlobalKey webViewKey = GlobalKey();
  List<String>? selectedFriendIds;

  @override
  void initState() {
    super.initState();

    if (widget.initialUrl != null) {
      // uri = WebUri(widget.initialUrl!); // WebUri로 변환
      // print('초기 URL: $uri');
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
      // appBar: AppBar(
      //   title: Text('Video Conference'),
      // ),
      // body: SafeArea(
      //   child: InAppWebView(
      //     key: webViewKey,
      //     initialUrlRequest: URLRequest(
      //       // WebUri가 null이 아닌 경우 해당 URL, 그렇지 않으면 기본 URL 사용
      //       url: uri ??
      //           WebUri(
      //               'https://vervet-sacred-needlessly.ngrok-free.app/roomId?roomId=$roomId'),
      //     ),
      //     initialSettings: InAppWebViewSettings(
      //       javaScriptEnabled: true,
      //       mediaPlaybackRequiresUserGesture: false,
      //       allowBackgroundAudioPlaying: true,
      //       allowsInlineMediaPlayback: true,
      //       useHybridComposition: true,
      //       allowsPictureInPictureMediaPlayback: true,
      //     ),
      //     onWebViewCreated: (InAppWebViewController controller) {
      //       setState(() {
      //         _webViewController = controller;
      //       });
      //
      //       _webViewController?.addJavaScriptHandler(
      //           handlerName: 'goToHomeScreen',
      //           callback: (args) {
      //             Navigator.of(context).popUntil((route) => route.isFirst);
      //           });
      //     },
      //     onJsAlert: (controller, jsAlertRequest) async {
      //       print(jsAlertRequest.message);
      //       await showDialog(
      //         context: context,
      //         builder: (context) {
      //           return AlertDialog(
      //             title: Text("알림"),
      //             content: Text(jsAlertRequest.message ?? "No message"),
      //             actions: [
      //               TextButton(
      //                 onPressed: () {
      //                   Navigator.of(context).pop();
      //                 },
      //                 child: Text("OK"),
      //               ),
      //             ],
      //           );
      //         },
      //       );
      //       await controller.evaluateJavascript(source: '''
      //         var videos = document.querySelectorAll('video');
      //         videos.forEach(function(video) {
      //           video.play();
      //         });
      //       ''');
      //       return JsAlertResponse(handledByClient: true);
      //     },
      //     onPermissionRequest:
      //         (InAppWebViewController controller, request) async {
      //       return PermissionResponse(
      //         resources: request.resources,
      //         action: PermissionResponseAction.GRANT,
      //       );
      //     },
      //     onConsoleMessage: (controller, consoleMessage) {
      //       print(consoleMessage.message);
      //     },
      //   ),
      // ),
    );
  }
}
