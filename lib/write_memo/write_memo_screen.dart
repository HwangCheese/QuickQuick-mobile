import 'package:convert/convert.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sticker_memo/globals.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:io';

class WriteMemoScreen extends StatefulWidget {
  final String? initialText;
  final Color? initialColor;
  final String? initialDataId;

  WriteMemoScreen({this.initialText, this.initialColor, this.initialDataId});

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
  String? _imagePath;
  String? _filePath;
  bool _isImageSelected = false;

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
      final fileExtension = _imagePath!.split('.').last;
      body['format'] = fileExtension;
      print(fileExtension);
      await _uploadImage(_imagePath!, body);
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
                      _imagePath = pickedFile.path;
                      _filePath = null;
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
                      _imagePath = pickedFile.path;
                      _filePath = null;
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
                      _imagePath = null;
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

  Future<List<int>> readImageAsBlob(String imagePath) async {
    final file = File(imagePath);
    return await file.readAsBytes();
  }

  Future<void> writeBlobToImage(List<int> blobData, String outputPath) async {
    final file = File(outputPath);
    await file.writeAsBytes(blobData);
  }

  Future<void> saveBlobAsHex(List<int> blobData, String hexOutputPath) async {
    final file = File(hexOutputPath);
    final hexData = hex.encode(blobData);
    await file.writeAsString(hexData);
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Color(0xFFE2F1FF),
      appBar: AppBar(
        backgroundColor: Color(0xFFE2F1FF),
        leading: BackButton(
          onPressed: () async {
            await _saveMemoToServer();
            Navigator.pop(context, {
              'text': _controller.text,
              'color': _backgroundColor,
              'isPinned': false,
            });
          },
        ),
        title: Text('메모 작성'),
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
                SizedBox(
                  width: screenWidth * 0.9,
                  height: screenHeight * 0.6,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 20, // 원하는 만큼 아래로 내리기
                        left: 0,
                        right: 0,
                        bottom: 0, // 공간을 확보하여 TextField가 Stack 내에서 위치를 유지
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _backgroundColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_imagePath != null)
                        Positioned.fill(
                          child: Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      if (_filePath != null)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            color: Colors.white,
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'File attached: ${_filePath!.split('/').last}',
                              style: TextStyle(color: Colors.black),
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
                      onPressed: _showFriendSelectionDialog,
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
