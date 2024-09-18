import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:sticker_memo/screens/friends_list/friends_list_screen.dart';
import 'package:sticker_memo/screens/video_call/video_call_screen.dart';
import 'package:sticker_memo/screens/write_memo/write_memo_screen.dart';
import './globals.dart';
import 'main.dart';

class SocketService {
  List<Map<String, dynamic>> memos = [];
  static final SocketService _instance = SocketService._internal();
  IO.Socket? socket;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  String? notificationMemoId;

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    _initializeNotification();
    _initializeSocket();
  }

  final NotificationDetails details = const NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
    android: AndroidNotificationDetails(
      "1",
      "test",
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  Map<String, Color> colorMap = {
    'white': Colors.white,
    'pink': Colors.pink[100]!,
    'blue': Colors.blue[100]!,
    'green': Colors.green[100]!,
    'orange': Colors.orange[100]!,
    'yellow': Colors.yellow[100]!,
    'purple': Colors.purple[100]!,
    'grey': Colors.grey[300]!,
  };

  Future<void> _initializeNotification() async {
    if (await Permission.notification.isDenied &&
        !await Permission.notification.isPermanentlyDenied) {
      await [Permission.notification].request();
    }

    const AndroidInitializationSettings android =
        AndroidInitializationSettings("@mipmap/ic_launcher");
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    final InitializationSettings settings =
        InitializationSettings(android: android, iOS: ios);

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          String payload = response.payload!;
          if (payload.startsWith('https')) {
            // If the payload is a URL, open VideoCallScreen with the URL
            MyApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => VideoCallScreen(
                  initialUrl: payload,
                ),
              ),
            );
          } else if (payload == 'add-friend') {
            final friendsList = await _fetchFriends();
            bool isAlreadyFriend = friendsList
                .any((friend) => friend['friend_user_name'] == USER_NAME);

            if (!isAlreadyFriend) {
              MyApp.navigatorKey.currentState
                  ?.push(
                MaterialPageRoute(
                  builder: (context) => FriendsListScreen(),
                ),
              )
                  .then((_) {
                FriendsListScreenState? state = MyApp
                    .navigatorKey.currentState?.context
                    .findAncestorStateOfType<FriendsListScreenState>();
                state?.showAddFriendDialog();
              });
            } else {
              MyApp.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (context) => FriendsListScreen(),
                ),
              );
            }
          } else if (payload == 'kock') {
            MyApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => FriendsListScreen(),
              ),
            );
          } else {
            await _fetchMemos();
            final memoId = payload;
            Color? memoColor;
            for (var memo in memos) {
              if (memo['memo_id'] == memoId) {
                memoColor = memo['color'];
                break;
              }
            }
            MyApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => WriteMemoScreen(
                  initialMemoId: memoId,
                  initialColor: memoColor,
                ),
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _sendNotification(
      String status, String message, String? memoId) async {
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _local.show(notificationId, status, message, details,
        payload: memoId);
  }

  void _initializeSocket() {
    // 소켓 서버와의 연결 설정
    socket = IO.io('$SERVER_IP', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false, // autoConnect: false 설정
    });

    socket!.connect(); // 소켓 연결 시도

    // 소켓 연결 성공 확인
    socket!.on('connect', (_) {
      print('Connected to server'); // 연결 성공시 로그
      String user = USER_ID + ";" + USER_NAME;
      socket!.emit('join-room', user);
    });

    socket!.on('add-friend', (data) {
      print('Received notification: $data');
      _sendNotification('친구 추가', data, 'add-friend');
    });

    socket!.on('new-memo', (data) async {
      print('Received message: $data');
      if (data is List && data.length >= 2) {
        String message = data[0]; // 첫 번째 인자 (메시지)
        String memoId = data[1]; // 두 번째 인자 (메모 ID)

        print('Received message: $message');
        print('Received memoId: $memoId');

        // 알림 표시
        _sendNotification('메모가 도착했어요!', message, memoId);
      } else {
        print('Unexpected data format');
      }
    });

    socket!.on('kock', (message) {
      _sendNotification('콕!', message, 'kock');
    });

    socket!.on('invite', (message) {
      _sendNotification('화상회의 초대', '화상 회의 요청이 왔어요!', message);
    });

    // 소켓 연결 실패 시 에러 로그
    socket!.on('connect_error', (error) {
      print('Connection Error: $error'); // 연결 실패시 로그
    });

    // 소켓 연결 끊김 확인
    socket!.on('disconnect', (_) {
      print('Disconnected from server'); // 연결 끊김 로그
    });
  }

  Future<void> _fetchMemos() async {
    final url = Uri.parse('$SERVER_IP/memo/$USER_ID');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> memo = json.decode(response.body);
        memos = memo.map((item) {
          String memoId = item['memo_id'];
          return {
            'color': colorMap[item['theme']] ?? Colors.white,
            'memo_id': memoId,
          };
        }).toList();
      } else {
        print('Failed to load memos: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memos: $e');
    }
  }

  Future<List<Map<String, String>>> _fetchFriends() async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);

      return data.map<Map<String, String>>((friend) {
        return {
          'friend_user_name': friend['friend_user_name'] ?? '',
          'friend_id': friend['friend_id'] ?? '',
        };
      }).toList();
    } else {
      print('Failed to load friends');
      return [];
    }
  }
}
