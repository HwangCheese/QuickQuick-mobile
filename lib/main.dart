import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../login/login_screen.dart';

void main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Memo',
      theme: ThemeData(scaffoldBackgroundColor: Colors.white),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ko', 'KR'),
      ],
      home: LogIn(),
    );
  }
}
