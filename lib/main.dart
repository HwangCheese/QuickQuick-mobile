import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticker_memo/screens/login/login_screen.dart';
import 'package:sticker_memo/screens/home/home_screen.dart';
import 'package:sticker_memo/socket_service.dart';
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

    SocketService();

    initialScreen = HomeScreen();
  } else {
    initialScreen = Login();
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Memo',
      theme: ThemeData(
          fontFamily: 'KakaoOTFRegular', scaffoldBackgroundColor: Colors.white),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ko', 'KR'),
      ],
      navigatorKey: navigatorKey,
      home: initialScreen,
    );
  }
}
