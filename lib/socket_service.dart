import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:sticker_memo/screens/write_memo/write_memo_screen.dart';
import './globals.dart';
import 'main.dart';

class SocketService {
  List<Map<String, dynamic>> memos = [];
  static final SocketService _instance = SocketService._internal();
  IO.Socket? socket;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

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
  }

  Future<void> _sendNotification(String status, String message) async {
    // 고유한 알림 ID를 생성 (현재 시간을 사용)
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _local.show(notificationId, status, message, details);
  }

  void _initializeSocket() {
    socket = IO.io('$SERVER_IP', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    socket!.on('connect', (_) {
      print('Connected to server');
      String user = USER_ID + ";" + USER_NAME;
      print(user);
      socket!.emit('join-room', user);
    });

    // 친구 추가 알림
    socket!.on('add-friend', (data) {
      print('Received notification: $data');
      _sendNotification('친구 추가', data);
    });

    // 'new-memo' 이벤트에서 받은 memoId와 fetchMemos에서 불러온 memoId 비교 후 색상 찾기
    socket!.on('new-memo', (data) async {
      print('Received message: $data');
      if (data is List && data.length >= 2) {
        String message = data[0]; // 첫 번째 인자 (메시지)
        String memoId = data[1]; // 두 번째 인자 (메모 ID)

        print('Received message: $message');
        print('Received memoId: $memoId');

        // 알림 표시
        _sendNotification('메모 수신', message);

        // 메모 목록 불러오기
        await _fetchMemos();

        // 불러온 메모 목록에서 memoId를 비교하여 색상 찾기
        Color? memoColor;
        for (var memo in memos) {
          if (memo['memo_id'] == memoId) {
            memoColor = memo['color']; // memoId가 일치하는 메모의 색상 저장
            break;
          }
        }

        // WriteMemoScreen으로 해당 메모 ID와 색상을 전달하여 화면 열기
        MyApp.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => WriteMemoScreen(
            initialMemoId: memoId, // 메모 ID 전달
            initialColor: memoColor, // 메모 색상 전달
          ),
        ));
      } else {
        print('Unexpected data format');
      }
    });

    socket!.on('kock', (message) {
      _sendNotification('콕!', message);
    });

    socket!.on('invite', (message) {
      _sendNotification('화상회의 초대', message);
    });

    socket!.on('connect_error', (error) {
      print('Connection Error: $error');
    });

    socket!.on('disconnect', (_) {
      print('Disconnected from server');
    });

    socket!.on(
        'existing_clients', (clients) => {print('Existing clients: $clients')});

    socket!.on(
        'new_client', (clientId) => {print('New client joined: $clientId')});
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
}
