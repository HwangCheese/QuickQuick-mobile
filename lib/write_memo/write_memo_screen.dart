import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // 이미지 선택
import 'package:file_picker/file_picker.dart'; // 파일 선택
// import 'package:flutter_sound/flutter_sound.dart'; // 음성 녹음
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'; // 권한 요청

import 'package:http/http.dart' as http; // HTTP 요청
import 'dart:convert'; // JSON 인코딩
import 'package:sticker_memo/globals.dart';

class WriteMemoScreen extends StatefulWidget {
  final String? initialText;
  final Color? initialColor;
  final String? initialDataId;

  WriteMemoScreen({this.initialText, this.initialColor, this.initialDataId});   // 기존 데이터 삭제를 위한 데이터 아이디 전달 추가 !!

  @override
  _WriteMemoScreenState createState() => _WriteMemoScreenState();
}

class _WriteMemoScreenState extends State<WriteMemoScreen> {
  final TextEditingController _controller = TextEditingController();
  Color _backgroundColor = Colors.white; // 초기 배경색을 흰색으로 설정

  final ImagePicker _picker = ImagePicker();
  //final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    //_initRecorder();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    if (widget.initialColor != null) {
      _backgroundColor = widget.initialColor!;
    }
    if (widget.initialDataId != null) {
      _deleteMemoFromServer(widget.initialDataId!);
    }
  }

  Future<void> _deleteMemoFromServer(String dataId) async {  // 메모 삭제요청 전송
    final url = Uri.parse('$SERVER_IP/data/$dataId');
    final response = await http.delete(url);
    if (response.statusCode == 200) {
      print('메모 삭제 성공');
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
    }
  }

  // Future<void> _initRecorder() async {
  //   try {
  //     // 권한 요청
  //     var status = await Permission.microphone.request();
  //     if (status != PermissionStatus.granted) {
  //       throw RecordingPermissionException('Microphone permission not granted');
  //     }
  //     await _recorder.openRecorder();
  //   } catch (e) {
  //     print("녹음기 초기화 오류: $e");
  //   }
  // }
  //
  // @override
  // void dispose() {
  //   _recorder.closeRecorder();
  //   super.dispose();
  // }

  // Future<void> _toggleRecording() async {
  //   try {
  //     if (_isRecording) {
  //       await _recorder.stopRecorder();
  //       setState(() {
  //         _isRecording = false;
  //       });
  //     } else {
  //       final directory = await getApplicationDocumentsDirectory();
  //       final filePath = '${directory.path}/audio_recording.aac';
  //       await _recorder.startRecorder(
  //         toFile: filePath,
  //         codec: Codec.aacADTS,
  //       );
  //       setState(() {
  //         _isRecording = true;
  //       });
  //     }
  //   } catch (e) {
  //     print("녹음 시작/중지 오류: $e");
  //   }
  // }

  Future<void> _saveMemoToServer() async {
    final url = Uri.parse('$SERVER_IP/data'); // 서버 주소
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'userId': USER_ID,
        'format': 'txt',
        'date': DateTime.now().toIso8601String(),
        'isOpen': true,
        'theme': _backgroundColor.value,
        'posX': 500,    //우선은 디폴트값 500,500,100,100 으로 ..
        'posY': 500,
        'width': 100,
        'height': 100,
        'data_txt': _controller.text,
      }),
    );

    if (response.statusCode == 201) {
      print('메모 저장 성공');
    } else {
      print('메모 저장 실패: ${response.statusCode}');
    }
  }


  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '배경색 선택',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16.0),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                children: <Color>[
                  Colors.pink[100]!,
                  Colors.blue[100]!,
                  Colors.green[100]!,
                  Colors.orange[100]!,
                  Colors.yellow[100]!,
                ].map((Color color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _backgroundColor = color;
                      });
                      Navigator.pop(context); // 색상 선택 후 닫기
                    },
                    child: Container(
                      margin: const EdgeInsets.all(8.0),
                      color: color,
                      width: 50.0,
                      height: 50.0,
                      child: Center(
                        child: _backgroundColor == color
                            ? Icon(Icons.check, color: Colors.black)
                            : SizedBox.shrink(),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImageOrFile() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('사진 찍기'),
                onTap: () async {
                  Navigator.pop(context);
                  final pickedFile =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (pickedFile != null) {
                    print('사진 경로: ${pickedFile.path}');
                    // 여기에서 선택한 사진을 처리
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('갤러리에서 선택'),
                onTap: () async {
                  Navigator.pop(context);
                  final pickedFile =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (pickedFile != null) {
                    print('사진 경로: ${pickedFile.path}');
                    // 여기에서 선택한 사진을 처리
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.attach_file),
                title: Text('파일 첨부'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: [
                      'jpg',
                      'png',
                      'wav',
                      'mp3',
                      'pdf',
                      'doc'
                    ],
                  );
                  if (result != null) {
                    final file = result.files.single;
                    print('파일 경로: ${file.path}');
                    // 여기에서 선택한 파일을 처리
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 화면 크기 가져오기
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Color(0xFFE2F1FF),
      appBar: AppBar(
        backgroundColor: Color(0xFFE2F1FF),
        leading: BackButton(
          onPressed: () async {
            await _saveMemoToServer();
            Navigator.pop(context, {
              'text': _controller.text,
              'color': _backgroundColor.value,
              'isPinned': false, // 기본값 설정
            }); // 작성한 내용과 색상 정보 전달
          },
        ),
        title: Text('메모 작성'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 세로 방향으로 중앙 배치
          children: <Widget>[
            SizedBox(
              width: screenWidth * 0.9, // 화면 너비의 90%로 설정
              height: screenHeight * 0.55, // 화면 높이의 55%로 설정
              child: TextField(
                controller: _controller, // 컨트롤러 설정
                maxLines: null, // 여러 줄 입력 허용
                expands: true, // 사용 가능한 공간을 채우도록 확장
                textAlignVertical: TextAlignVertical.top, // 텍스트 정렬을 위쪽으로 설정
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _backgroundColor, // 선택된 배경색으로 설정
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0), // 모서리 둥글게 만들기
                    borderSide: BorderSide.none, // 테두리 색 없애기
                  ),
                ),
              ),
            ),
            SizedBox(height: 50.0), // TextField와 아이콘 버튼 사이의 간격
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly, // 아이콘 버튼들을 균등하게 배치
              children: [
                IconButton(
                  iconSize: 45.0,
                  icon: const Icon(CupertinoIcons.paintbrush),
                  onPressed: _showColorPicker, // 색상 선택기 표시
                ),
                IconButton(
                  iconSize: 45.0,
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickImageOrFile, // 파일 선택기 표시
                ),
                IconButton(
                  iconSize: 45.0,
                  icon: _isRecording
                      ? Icon(Icons.stop, color: Colors.red) // 녹음 중일 때 Stop 아이콘
                      : Icon(CupertinoIcons.mic), // 기본 마이크 아이콘
                  onPressed: () {}, // 녹음 시작/중지 _toggleRecording
                ),
                IconButton(
                  iconSize: 45.0,
                  icon: const Icon(Icons.edit_note),
                  onPressed: () {},
                ),
                IconButton(
                  iconSize: 45.0,
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
