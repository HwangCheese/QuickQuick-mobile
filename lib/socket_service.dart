import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sticker_memo/screens/write_memo/write_memo_screen.dart';
import './globals.dart';
import 'main.dart';

class SocketService {
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
    await _local.initialize(settings,
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse);
  }

  Future<void> _sendNotification(String message) async {
    // message는 그대로 사용
    await _local.show(1, "알림", message, details);
  }

  void onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {
    final payload = notificationResponse.payload;
    if (payload != null) {
      // payload는 JSON 형식의 문자열이라고 가정합니다.
      // payload에서 memoId를 추출합니다.
      final data = jsonDecode(payload);
      final memoId = data['memoId'];

      if (memoId != null) {
        MyApp.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => WriteMemoScreen(
            initialMemoId: memoId,
          ),
        ));
      }
    }
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
      _sendNotification(data);
    });

    // 메모 수신 알림
    socket!.on('new-memo', (data) {
      print('Received message: $data');
      if (data is List && data.length >= 2) {
        String message = data[0]; // 첫 번째 인자 (메시지)
        String memoId = data[1]; // 두 번째 인자 (메모 ID)

        print('Received message: $message');
        print('Received memoId: $memoId');

        _sendNotification(message);
      } else {
        print('Unexpected data format');
      }
    });

    socket!.on('kock', (message) {
      print(message);
      _sendNotification(message);
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
}
