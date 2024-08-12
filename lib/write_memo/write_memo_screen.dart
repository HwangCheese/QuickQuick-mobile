import 'dart:typed_data'; // Uint8List를 사용하기 위해 추가
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:io';

import '../../globals.dart';

class WriteMemoScreen extends StatefulWidget {
  final String? initialText;
  final Color? initialColor;
  final String? initialDataId;
  final Uint8List? initialImageData; // 이미지 데이터를 받기 위한 매개변수 추가

  WriteMemoScreen({
    this.initialText,
    this.initialColor,
    this.initialDataId,
    this.initialImageData,
  });

  @override
  _WriteMemoScreenState createState() => _WriteMemoScreenState();
}

class _WriteMemoScreenState extends State<WriteMemoScreen> {
  final TextEditingController _controller = TextEditingController();
  Color _backgroundColor = Colors.white;
  final FocusNode _focusNode = FocusNode();

  final ImagePicker _picker = ImagePicker();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _audioPath;
  List<String> _imagePaths = [];
  String? _filePath;
  bool _isImageSelected = false;
  Uint8List? _imageData; // 이미지 데이터
  int? _selectedImageIndex; // 선택된 이미지 인덱스

  Map<String, Color> colorMap = {
    'pink': Colors.pink[100]!,
    'blue': Colors.blue[100]!,
    'green': Colors.green[100]!,
    'orange': Colors.orange[100]!,
    'yellow': Colors.yellow[100]!,
  };

  String getColorName(Color color) {
    return colorMap.entries
        .firstWhere((entry) => entry.value == color,
            orElse: () => MapEntry('white', Colors.white))
        .key;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    if (widget.initialColor != null) {
      _backgroundColor = widget.initialColor!;
    }
    if (widget.initialDataId != null) {
      _deleteMemoFromServer(widget.initialDataId!);
    }
    if (widget.initialImageData != null) {
      _isImageSelected = true;
      _imageData = widget.initialImageData; // 초기 이미지 데이터 설정
    }
    _initRecorder();
  }

  Future<void> _deleteMemoFromServer(String dataId) async {
    final url = Uri.parse('$SERVER_IP/data/$dataId');
    final response = await http.delete(url);
    if (response.statusCode == 200) {
      print('메모 삭제 성공');
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
    }
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
  }

  @override
  void dispose() {
    _controller.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<void> _saveMemoToServer() async {
    var url = Uri.parse('$SERVER_IP/data');
    final Map<String, dynamic> body = {
      'userId': USER_ID,
      'format': 'txt',
      'date': DateTime.now().toIso8601String(),
      'isOpen': true,
      'theme': getColorName(_backgroundColor),
      'posX': 500,
      'posY': 500,
      'width': 100,
      'height': 100,
      'data_txt': _controller.text,
      'audio_path': _audioPath,
    };

    if (_isImageSelected) {
      if (_imagePaths.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        for (var imagePath in _imagePaths) {
          final fileExtension = imagePath.split('.').last;
          body['format'] = fileExtension;
          await _uploadImage(imagePath, body);
        }
      } else if (_imageData != null) {
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/temp_image.png').create();
        await file.writeAsBytes(_imageData!);
        await _uploadImage(file.path, body);
      }
    } else if (_filePath != null) {
      final file = File(_filePath!);
      final fileBytes = await file.readAsBytes();
      final fileBase64 = base64Encode(fileBytes);
      final fileExtension = _filePath!.split('.').last;
      body['file_data'] = fileBase64;
      body['file_extension'] = fileExtension;
      body['file_path'] = _filePath;
    } else {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        print('메모 저장 성공');
      } else {
        print('메모 저장 실패: ${response.statusCode}');
      }
    }
  }

  Future<void> _uploadImage(String imagePath, Map<String, dynamic> body) async {
    final url = Uri.parse('$SERVER_IP/upload');
    final request = http.MultipartRequest('POST', url);

    request.fields
        .addAll(body.map((key, value) => MapEntry(key, value.toString())));
    request.files.add(await http.MultipartFile.fromPath('file', imagePath));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final responseData = jsonDecode(responseBody);

    if (response.statusCode == 201) {
      print('이미지 업로드 성공');
    } else {
      print('이미지 업로드 실패: ${response.statusCode}');
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
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() {
                        _backgroundColor = color;
                      });
                      Navigator.pop(context);
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
                    setState(() {
                      _isImageSelected = true;
                      _imagePaths.add(pickedFile.path);
                      _filePath = null;
                      _imageData = null;
                    });
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
                    setState(() {
                      _isImageSelected = true;
                      _imagePaths.add(pickedFile.path);
                      _filePath = null;
                      _imageData = null;
                    });
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
                    setState(() {
                      _filePath = result.files.single.path;
                      _imagePaths.clear();
                      _imageData = null;
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startRecording() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String filePath =
        '${appDocDir.path}/memo_audio_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.startRecorder(toFile: filePath, codec: Codec.aacADTS);
    setState(() {
      _isRecording = true;
      _audioPath = filePath;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });
  }

  Future<void> _saveAndShareMemo() async {
    try {
      // 메모를 서버에 저장합니다.
      await _saveMemoToServer();

      // 메모 저장이 성공하면 친구 목록을 표시합니다.
      _showFriendSelectionDialog();
    } catch (e) {
      // 저장 중 오류가 발생하면 메시지를 보여줍니다.
      _showMessage('메모 저장 중 오류가 발생했습니다.');
    }
  }

  Future<void> _shareMemoWithFriend(String friendUserId) async {
    final url = Uri.parse('$SERVER_IP/shareMemo');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'from_user_id': USER_ID,
        'to_user_id': friendUserId,
        'memo_id': widget.initialDataId,
      }),
    );

    if (response.statusCode == 200) {
      print('메모 공유 성공');
      _showMessage('메모가 성공적으로 공유되었습니다.');
    } else {
      print('메모 공유 실패: ${response.statusCode}');
      _showMessage('메모 공유에 실패했습니다.');
    }
  }

  Future<void> _showFriendSelectionDialog() async {
    final response =
        await http.get(Uri.parse('${SERVER_IP}/friends/${USER_ID}'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, String>> friends = data
          .map<Map<String, String>>((friend) => {
                'user_id': friend['user_id'],
                'user_name': friend['user_name'],
              })
          .toList();

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('친구 선택'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(friends[index]['user_name']!),
                    onTap: () {
                      Navigator.pop(context);
                      _shareMemoWithFriend(friends[index]['user_id']!);
                    },
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('취소'),
              ),
            ],
          );
        },
      );
    } else {
      _showMessage('친구 목록을 불러오는 데 실패했습니다.');
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _removeImage(int index) {
    setState(() {
      _imagePaths.removeAt(index);
      _selectedImageIndex = null;
    });
  }

  void _toggleImageSelection(int index) {
    setState(() {
      if (_selectedImageIndex == index) {
        _selectedImageIndex = null; // 선택된 이미지가 다시 터치되면 선택 해제
      } else {
        _selectedImageIndex = index; // 해당 이미지를 선택
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Color(0xFFE2F1FF), // 기존 파란색 배경 유지
      appBar: AppBar(
        backgroundColor: Color(0xFFE2F1FF), // AppBar 배경도 파란색으로 유지
        leading: BackButton(
          color: Colors.black, // 뒤로가기 버튼 색상 설정
          onPressed: () async {
            await _saveMemoToServer();
            Navigator.pop(context, {
              'text': _controller.text,
              'color': _backgroundColor,
              'isPinned': false,
              'dataId': widget.initialDataId,
            });
          },
        ),
        title:
            Text('메모 작성', style: TextStyle(color: Colors.black)), // 제목 글자 색상 설정
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // 키보드 내리기
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: screenWidth * 0.9,
                  height: screenHeight * 0.6,
                  decoration: BoxDecoration(
                    color: Colors.white, // 이미지와 메모 영역 배경을 흰색으로 설정
                    borderRadius: BorderRadius.circular(16.0), // 모서리를 둥글게 설정
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (_imagePaths.isNotEmpty)
                        Expanded(
                          flex: 3,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _imagePaths.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () => _toggleImageSelection(index),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0),
                                      child: AspectRatio(
                                        aspectRatio: 1.0, // 정사각형 비율 유지
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              16.0), // 이미지 모서리 둥글게 설정
                                          child: Image.file(
                                            File(_imagePaths[index]),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_selectedImageIndex == index)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () => _removeImage(index),
                                          child: CircleAvatar(
                                            backgroundColor: Colors.grey,
                                            radius: 16,
                                            child: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      if (_filePath != null)
                        Container(
                          color: Colors.white,
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'File attached: ${_filePath!.split('/').last}',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white, // 메모 입력 필드 배경을 흰색으로 설정
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  16.0), // 텍스트 필드 모서리를 둥글게 설정
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 70.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 45.0,
                      icon: const Icon(CupertinoIcons.paintbrush),
                      onPressed: _showColorPicker,
                    ),
                    IconButton(
                      iconSize: 45.0,
                      icon: const Icon(Icons.attach_file),
                      onPressed: _pickImageOrFile,
                    ),
                    IconButton(
                      iconSize: 45.0,
                      icon: _isRecording
                          ? Icon(Icons.stop, color: Colors.red)
                          : Icon(CupertinoIcons.mic),
                      onPressed:
                          _isRecording ? _stopRecording : _startRecording,
                    ),
                    IconButton(
                      iconSize: 45.0,
                      icon: const Icon(Icons.edit_note),
                      onPressed: () {},
                    ),
                    IconButton(
                      iconSize: 45.0,
                      icon: const Icon(Icons.send_rounded),
                      onPressed: _saveAndShareMemo,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
