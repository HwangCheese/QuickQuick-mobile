import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_memo/screens/login/login_screen.dart';
import 'package:sticker_memo/screens/home/home_screen.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'globals.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final userId = prefs.getString('userId');
  final userName = prefs.getString('userName');

  Widget initialScreen;

  if (token != null && userId != null && userName != null) {
    USER_ID = userId;
    USER_NAME = userName;

    IO.Socket socket = IO.io('$SERVER_IP', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.on('connect', (_) {
      print('Connected to server');
      String user = USER_ID + ";" + USER_NAME;
      socket.emit('join-room', user);
    });

    socket.on('connect_error', (error) {
      print('Connection Error: $error');
    });

    socket.on('disconnect', (_) {
      print('Disconnected from server');
    });

    socket.connect();

    print("사용자 이름: $USER_NAME");
    print('소켓 연결 상태: ${socket.connected}');

    initialScreen = HomeScreen();
  } else {
    initialScreen = Login();
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Memo',
      theme: ThemeData(
          fontFamily: 'IBMPlexSansKR', scaffoldBackgroundColor: Colors.white),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ko', 'KR'),
      ],
      home: initialScreen,
    );
  }
}
