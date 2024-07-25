import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // http 패키지 추가
import 'dart:convert';
import 'package:sticker_memo/home/home_screen.dart'; // json 데이터로 인코딩을 도와주는 라이브러리

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LogIn(),
    );
  }
}

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  TextEditingController controller = TextEditingController();
  TextEditingController controller2 = TextEditingController();

  // 로그인 입니다.
  Future<void> loginUser(String userNumber, String password) async {
    if (userNumber == '1111' && password == '1111') {
      // 로컬에서 ID와 PW가 1111인 경우
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
      return;
    }

    final url = Uri.parse('http://223.194.130.27:3000/login');
    try {
      final response = await http.post(
        // post 요청을 서버로 전송할게요~
        url,
        headers: {
          'Content-Type': 'application/json', // json 타입으로
        },
        body: jsonEncode({
          'user_number': userNumber,
          'user_pw': password,
        }),
      );

      // 밑의 코드는 오류검증 코드인데 아직 작동을 확인하지는 못함
      if (response.statusCode == 200) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        final responseBody = jsonDecode(response.body);
        showSnackBar(context, Text(responseBody['error']));
      }
    } catch (e) {
      showSnackBar(context, Text('서버에 연결할 수 없습니다. 네트워크 상태를 확인해주세요.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Padding(padding: EdgeInsets.only(top: 50)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 50.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 40.0,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 35.0),
              Form(
                child: Container(
                  padding: EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '전화번호',
                          fillColor: Color(0xFFE2F1FF),
                          filled: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 12.0),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 5.0),
                            child: Icon(Icons.local_post_office_outlined,
                                size: 24.0, color: Colors.grey),
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      SizedBox(height: 20.0),
                      TextField(
                        controller: controller2,
                        decoration: InputDecoration(
                          hintText: '비밀번호(4자리)',
                          fillColor: Color(0xFFE2F1FF),
                          filled: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 12.0),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 5.0),
                            child: Icon(Icons.lock_outline,
                                size: 24.0, color: Colors.grey),
                          ),
                        ),
                        keyboardType: TextInputType.text,
                        obscureText: true,
                      ),
                      SizedBox(height: 40.0),
                      Center(
                        child: SizedBox(
                          width: 180,
                          child: ElevatedButton(
                            onPressed: () {
                              loginUser(controller.text, controller2.text);
                            },
                            child: Text(
                              '로그인',
                              style: TextStyle(
                                fontSize: 18.0,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFFCDE9FF),
                                minimumSize: Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showSnackBar(BuildContext context, Text text) {
  final snackBar = SnackBar(
    content: text,
    backgroundColor: const Color.fromARGB(255, 112, 48, 48),
  );

  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}
