import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import './globals.dart';

class SocketService {
  IO.Socket? socket;
  final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();

  SocketService() {
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
    await _local.initialize(settings);
  }

  Future<void> _sendNotification(String data) async {
    await _local.show(1, "알림", data, details);
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
      socket!.emit('join-room', user);
    });

    // 친구 추가 알림
    socket!.on('add-friend', (data) {
      print('Received notification: $data');
      _sendNotification(data);
    });

    // 메모 수신 알림
    socket!.on('new-memo', (data) {
      print('Received notification: $data');
      _sendNotification(data);
    });

    socket!.on('connect_error', (error) {
      print('Connection Error: $error');
    });

    socket!.on('disconnect', (_) {
      print('Disconnected from server');
    });

    socket!.on('existing_clients', (clients) => {
      print('Existing clients: $clients')


    });

    socket!.on('new_client', (clientId) => {
      print('New client joined: $clientId')
    });

    socket!.on('webrtc_offer', (data) => {

    });

    socket!.on('webrtc_answer', (data) => {

    });

    socket!.on('webrtc_ice_candidate', (data) => {

    });
  }
}
