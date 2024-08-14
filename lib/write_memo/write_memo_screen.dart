import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import '../../globals.dart';
import 'package:sticker_memo/api_service.dart';

class WriteMemoScreen extends StatefulWidget {
  final String? initialText;
  final Color? initialColor;
  String? initialMemoId;
  final Uint8List? initialImageData;

  WriteMemoScreen({
    this.initialText,
    this.initialColor,
    this.initialMemoId,
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
  List<String> _mediaPaths = [];
  String? _filePath;
  List<String> _filePaths = [];
  bool _isMediaSelected = false;
  Uint8List? _imageData;
  int? _selectedMediaIndex;
  List<VideoPlayerController?> _videoControllers = [];
  late ApiService _apiService;
  late MemoSummarizer _memoSummarizer;
  String _summary = '';
  String _originalText = '';
  bool _isLoading = false;

  Map<String, Color> colorMap = {
    'white': Colors.white,
    'pink': Colors.pink[100]!,
    'blue': Colors.blue[100]!,
    'green': Colors.green[100]!,
    'orange': Colors.orange[100]!,
    'yellow': Colors.yellow[100]!,
    'purple': Colors.purple[100]!,
    'grey': Colors.grey[300]!,
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
    _apiService = ApiService();
    _memoSummarizer = MemoSummarizer(_apiService);
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
      _originalText = widget.initialText!; // 저장 원본 텍스트
    }
    if (widget.initialColor != null) {
      _backgroundColor = widget.initialColor!;
    }
    if (widget.initialMemoId != null) {
      _deleteMemoFromServer(widget.initialMemoId!);
    }
    if (widget.initialImageData != null) {
      _isMediaSelected = true;
      _imageData = widget.initialImageData;
    }
    _initRecorder();
    _videoControllers = []; // Initialize as an empty growable list
  }

  Future<String> getSummary(String text) async {
    try {
      final response = await http.post(
        Uri.parse('http://$SERVER_IP/summary'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('summary')) {
          return data['summary'] as String;
        } else {
          throw Exception('API 응답에서 요약을 찾을 수 없습니다.');
        }
      } else {
        throw Exception('API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('요약 요청 실패: $e');
      return '요약을 가져오는 데 실패했습니다.';
    }
  }

  Future<void> _summarizeText() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summary = await _memoSummarizer.getSummary(_controller.text);

      setState(() {
        _summary = summary;
      });
    } catch (e) {
      print('요약을 가져오는 중 오류 발생: $e');
      setState(() {
        _summary = '요약을 가져오는 데 실패했습니다.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _restoreOriginalText() {
    setState(() {
      _controller.text = _originalText;
      _summary = ''; // 요약 초기화
    });
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
    for (var controller in _videoControllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  static String _generateRandomId() {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        16, (_) => characters.codeUnitAt(random.nextInt(characters.length))));
  }

  Future<void> _saveMemoToServer() async {
    widget.initialMemoId = _generateRandomId();
    var url = Uri.parse('$SERVER_IP/memo');
    var request = http.MultipartRequest('POST', url);

    request.fields['userId'] = USER_ID;
    request.fields['isOpen'] = '1'; // Assuming the memo is public
    request.fields['theme'] = getColorName(_backgroundColor);
    request.fields['posX'] = '100'; // Example position and size
    request.fields['posY'] = '100';
    request.fields['width'] = '400';
    request.fields['height'] = '300';
    request.fields['memo_id'] = widget.initialMemoId!;

    // Adding text content
    if (_controller.text.isNotEmpty) {
      request.fields['data_txt'] = _controller.text;
    } else {
      request.fields['data_txt'] = "";
    }

    for (var filePath in _mediaPaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    for (var filePath in _filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    var response = await request.send();
    if (response.statusCode == 201) {
      print('메모 저장 성공');
    } else {
      print('메모 저장 실패: ${response.statusCode}');
    }
  }

  Future<void> _uploadMedia(String mediaPath, Map<String, dynamic> body) async {
    final url = Uri.parse('$SERVER_IP/upload');
    final request = http.MultipartRequest('POST', url);

    request.fields
        .addAll(body.map((key, value) => MapEntry(key, value.toString())));
    request.files.add(await http.MultipartFile.fromPath('file', mediaPath));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final responseData = jsonDecode(responseBody);

    if (response.statusCode == 201) {
      print('미디어 업로드 성공');
    } else {
      print('미디어 업로드 실패: ${response.statusCode}');
    }
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
                title: Text('사진 또는 비디오 촬영'),
                onTap: () async {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return Container(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ListTile(
                              leading: Icon(Icons.photo_camera),
                              title: Text('사진 촬영'),
                              onTap: () async {
                                Navigator.pop(context);
                                final pickedFile = await _picker.pickImage(
                                    source: ImageSource.camera);
                                if (pickedFile != null) {
                                  setState(() {
                                    _isMediaSelected = true;
                                    _mediaPaths.add(pickedFile.path);
                                    _filePath = null;
                                    _imageData = null;
                                    _videoControllers.add(null);
                                  });
                                }
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.videocam),
                              title: Text('비디오 촬영'),
                              onTap: () async {
                                Navigator.pop(context);
                                final pickedFile = await _picker.pickVideo(
                                    source: ImageSource.camera);
                                if (pickedFile != null) {
                                  setState(() {
                                    _isMediaSelected = true;
                                    _mediaPaths.add(pickedFile.path);
                                    _filePath = null;
                                    _imageData = null;
                                    _videoControllers.add(null);
                                    _initializeVideoController(pickedFile.path,
                                        _mediaPaths.length - 1);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('갤러리에서 선택'),
                onTap: () async {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return Container(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ListTile(
                              leading: Icon(Icons.photo),
                              title: Text('사진 선택'),
                              onTap: () async {
                                Navigator.pop(context);
                                final pickedFile = await _picker.pickImage(
                                    source: ImageSource.gallery);
                                if (pickedFile != null) {
                                  setState(() {
                                    _isMediaSelected = true;
                                    _mediaPaths.add(pickedFile.path);
                                    _filePath = null;
                                    _imageData = null;
                                    _videoControllers.add(null);
                                  });
                                }
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.video_library),
                              title: Text('비디오 선택'),
                              onTap: () async {
                                Navigator.pop(context);
                                final pickedFile = await _picker.pickVideo(
                                    source: ImageSource.gallery);
                                if (pickedFile != null) {
                                  setState(() {
                                    _isMediaSelected = true;
                                    _mediaPaths.add(pickedFile.path);
                                    _filePath = null;
                                    _imageData = null;
                                    _videoControllers.add(null);
                                    _initializeVideoController(pickedFile.path,
                                        _mediaPaths.length - 1);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.attach_file),
                title: Text('파일 첨부'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                  );
                  if (result != null) {
                    setState(() {
                      _filePath = result.files.single.path;
                      _filePaths.add(_filePath!);
                      _mediaPaths.clear();
                      _videoControllers.clear();
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

  void _initializeVideoController(String videoPath, int index) {
    final controller = VideoPlayerController.file(File(videoPath));
    controller.initialize().then((_) {
      setState(() {
        if (_videoControllers.length <= index) {
          _videoControllers.add(controller);
        } else {
          _videoControllers[index] = controller;
        }
        _videoControllers[index]?.play(); // Auto-play the video
      });
    });
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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final file = File(result.files.single.path!);
      setState(() {
        _filePath = file.path;
        _filePaths.add(_filePath!);
      });
    }
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
    final url = Uri.parse('$SERVER_IP/send-memo');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'sourceUserId': USER_ID,
        'targetUserId': friendUserId,
        'memoId': widget.initialMemoId,
      }),
    );

    if (response.statusCode == 200) {
      print('메모 공유 성공');
      _showMessage('메모가 성공적으로 공유되었습니다.');
    } else {
      print('$USER_ID, $friendUserId, ${widget.initialMemoId}');
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

  void _removeMedia(int index) {
    setState(() {
      _mediaPaths.removeAt(index);
      if (_videoControllers[index] != null) {
        _videoControllers[index]?.dispose();
        _videoControllers.removeAt(index);
      }
      _selectedMediaIndex = null;
    });
  }

  void _toggleMediaSelection(int index) {
    setState(() {
      if (_selectedMediaIndex == index) {
        _selectedMediaIndex = null; // 선택된 미디어가 다시 터치되면 선택 해제
        if (_videoControllers[index] != null &&
            _videoControllers[index]!.value.isInitialized) {
          if (_videoControllers[index]!.value.isPlaying) {
            _videoControllers[index]!.pause();
          } else {
            _videoControllers[index]!.seekTo(Duration.zero);
            _videoControllers[index]!.play();
          }
        }
      } else {
        _selectedMediaIndex = index; // 해당 미디어를 선택
        if (_mediaPaths[index].endsWith('.mp4') ||
            _mediaPaths[index].endsWith('.MOV') ||
            _mediaPaths[index].endsWith('.mov')) {
          if (_videoControllers[index] == null) {
            _initializeVideoController(_mediaPaths[index], index);
          } else {
            if (!_videoControllers[index]!.value.isPlaying) {
              _videoControllers[index]!.play();
            }
          }
        }
      }
    });
  }

  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    debugPrint('Color Map Entries: ${colorMap.entries}');
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Color(0xFFE2F1FF), // 기존 파란색 배경 유지
      appBar: AppBar(
        backgroundColor: Color(0xFFE2F1FF), // AppBar 배경색
        leading: Padding(
          padding: const EdgeInsets.only(
              left: 16.0), // Left padding for the back button
          child: BackButton(
            color: Colors.black, // 뒤로가기 버튼 색상
            onPressed: () async {
              await _saveMemoToServer(); // 메모를 서버에 저장
              Navigator.pop(context, {
                'text': _controller.text,
                'color': _backgroundColor,
                'memo_id': widget.initialMemoId,
              });
            },
          ),
        ),
        title: Text('메모 작성', style: TextStyle(color: Colors.black)), // 제목 글자 색상
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0), // Horizontal padding for actions
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SizedBox(width: 16.0), // Add space between icons
                IconButton(
                  iconSize: 30.0,
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickImageOrFile,
                ),
                SizedBox(width: 16.0), // Add space between icons
                IconButton(
                  iconSize: 30.0,
                  icon: _isRecording
                      ? Icon(Icons.stop, color: Colors.red)
                      : Icon(CupertinoIcons.mic),
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                ),
                SizedBox(width: 16.0), // Add space between icons
                IconButton(
                  iconSize: 30.0,
                  icon: const Icon(Icons.edit_note),
                  onPressed: () async {
                    await _summarizeText(); // 텍스트 요약 요청
                  },
                ),
                SizedBox(width: 16.0), // Add space between icons
                IconButton(
                  iconSize: 30.0,
                  icon: Icon(Icons.send_rounded, color: Colors.black),
                  onPressed: _saveAndShareMemo,
                ),
              ],
            ),
          ),
        ],
      ),

      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // 키보드 내리기
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: 20.0),
              Container(
                width: screenWidth * 0.9,
                height: screenHeight * 0.6,
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: BorderRadius.circular(16.0),
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
                    if (_mediaPaths.isNotEmpty)
                      Expanded(
                        flex: 3,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _mediaPaths.length,
                          itemBuilder: (context, index) {
                            final filePath = _mediaPaths[index];
                            final isVideo = filePath.endsWith('.mp4') ||
                                filePath.endsWith('.MOV') ||
                                filePath.endsWith('.mov');
                            return GestureDetector(
                              onTap: () => _toggleMediaSelection(index),
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8.0, horizontal: 8.0),
                                    child: AspectRatio(
                                      aspectRatio:
                                          1.0, // Maintain square aspect ratio
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            16.0), // Rounded corners for media
                                        child: isVideo
                                            ? _videoControllers[index] !=
                                                        null &&
                                                    _videoControllers[index]!
                                                        .value
                                                        .isInitialized
                                                ? VideoPlayer(
                                                    _videoControllers[index]!)
                                                : Center(
                                                    child:
                                                        CircularProgressIndicator())
                                            : Image.file(
                                                File(filePath),
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                    ),
                                  ),
                                  if (_selectedMediaIndex == index)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: () => _removeMedia(index),
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
                          _filePath!.split('/').last,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '메모를 입력하세요...',
                          ),
                          style: TextStyle(
                            fontSize: 16.0,
                            color: Colors.black,
                          ),
                          onChanged: (value) {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.0),
              if (_summary.isNotEmpty)
                Container(
                  width: screenWidth * 0.9,
                  padding: EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '요약:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18.0,
                        ),
                      ),
                      SizedBox(height: 8.0),
                      Text(
                        _summary,
                        style: TextStyle(
                          fontSize: 16.0,
                        ),
                      ),
                      if (_originalText.isNotEmpty) // 원본 텍스트로 복원 버튼
                        TextButton(
                          onPressed: _restoreOriginalText,
                          child: Text('원본으로 되돌리기'),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: 20.0),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width:
                        MediaQuery.of(context).size.width, // 텍스트 필드와 가로 길이 맞추기
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: colorMap.entries.map((entry) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _backgroundColor = entry.value;
                              });
                            },
                            child: Container(
                              margin: EdgeInsets.symmetric(horizontal: 3),
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: entry.value,
                                borderRadius: BorderRadius.circular(20.0),
                                border: Border.all(
                                  color: _backgroundColor == entry.value
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2.0,
                                ),
                              ),
                              child: Center(
                                child: _backgroundColor == entry.value
                                    ? Icon(Icons.check, color: Colors.black)
                                    : SizedBox.shrink(),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
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
