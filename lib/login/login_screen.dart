import 'dart:convert'; // jsonEncode를 사용하기 위해 import
import '../../globals.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;

import '../home/home_screen.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Login(),
    );
  }
}

class Login extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? qrViewController;
  String? scanResult; // QR 코드에서 읽은 데이터를 저장할 변수
  bool showLoginButton = false; // 로그인 버튼을 보여줄지 여부를 결정하는 변수

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('QR을 스캔하여 퀵퀵이 서비스를 이용하세요'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: showLoginButton
                  ? ElevatedButton(
                      onPressed: _handleLogin,
                      child: Text('로그인'),
                    )
                  : Text('스캔한 데이터: ${scanResult ?? '없음'}'),
            ),
          ),
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      qrViewController = controller;
    });

    controller.scannedDataStream.listen((scanData) {
      setState(() {
        scanResult = scanData.code;
        showLoginButton = true; // QR 코드 스캔 후 버튼을 보여줍니다.
      });
    });
  }

  Future<void> _handleLogin() async {
    if (scanResult == null) {
      return;
    }

    // QR 코드에서 받은 데이터를 바로 사용 (이제 토큰만 포함됨)
    final String token = scanResult!;

    try {
      final response = await http.post(
        Uri.parse('$SERVER_IP/login-mobile'), // 로그인 요청 URL
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token, // 토큰만 전달합니다.
        }),
      );

      if (response.statusCode == 200) {
        print('로그인 성공: ${token}');

        // 로그인 성공 후 사용자 ID를 가져오는 함수 호출
        final String? userId = await _fetchUserId(token);

        if (userId != null) {
          print('사용자 ID: $userId');
          USER_ID = userId;

          // 홈 화면으로 이동
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        } else {
          print('사용자 ID 가져오기 실패');
        }
      } else {
        print('로그인 실패: ${response.statusCode}');
        print('응답 본문: ${response.body}');
      }
    } catch (e) {
      print('로그인 요청 오류: $e');
    }
  }

  Future<String?> _fetchUserId(String token) async {
    try {
      // 쿼리 파라미터로 토큰을 전달하기 위해 Uri를 생성
      final uri = Uri.parse('$SERVER_IP/get-userid').replace(queryParameters: {
        'token': token,
      });

      final response = await http.get(
        uri, // 쿼리 파라미터가 포함된 URI
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        USER_ID = responseData['id'];
        USER_NAME = responseData['name'];
        print('사용자 이름: $USER_NAME');
        return USER_ID; // 응답에서 사용자 ID를 추출
      } else {
        print('사용자 ID 요청 실패: ${response.statusCode}');
        print('응답 본문: ${response.body}');
        return null;
      }
    } catch (e) {
      print('사용자 ID 요청 오류: $e');
      return null;
    }
  }

  @override
  void dispose() {
    qrViewController?.dispose();
    super.dispose();
  }
}
