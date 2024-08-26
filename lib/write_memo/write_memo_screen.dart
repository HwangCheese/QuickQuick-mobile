import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
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
import '../calendar/calendar_screen.dart';
import 'media_viewer.dart';

class WriteMemoScreen extends StatefulWidget {
  final Color? initialColor;
  String? initialMemoId;
  final Uint8List? initialImageData;

  WriteMemoScreen({
    this.initialColor,
    this.initialMemoId,
    this.initialImageData,
  });

  @override
  _WriteMemoScreenState createState() => _WriteMemoScreenState();
}

class _WriteMemoScreenState extends State<WriteMemoScreen> {
  final TextEditingController _controller = TextEditingController();
  final _textController = TextEditingController(); // 번역에서 사용
  Color _backgroundColor = Colors.white;
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _audioPath;
  bool _isRecording = false;
  List<String> _mediaPaths = [];
  String? _filePath;
  List<String> _filePaths = [];
  bool _isMediaSelected = false;
  Uint8List? _imageData;
  int? _selectedMediaIndex;
  List<Uint8List> _fetchedImages = [];
  List<VideoPlayerController?> _videoControllers = [];
  String _summary = '';
  String _originalText = '';
  bool _isLoading = true; // 로딩 상태를 추가
  String _translatedText = '';
  String _selectedLanguage = 'ko';
  final String _textToProcess = '';
  bool _shouldShowSummaryRecommendation = false;
  final Record _recorder = Record();
  final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();
  String _transcription = ''; // 트랜스크립션 결과를 저장할 변수

  String? _initialText;
  Color? _initialBackgroundColor;
  List<String> _initialMediaPaths = [];

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

  final List<String> _languages = [
    'en', // 영어
    'es', // 스페인어
    'fr', // 프랑스어
    'de', // 독일어
    'ja', // 일본어
    'ko', // 한국어
  ];

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'es':
        return 'Spanish';
      case 'fr':
        return 'French';
      case 'de':
        return 'German';
      case 'ja':
        return 'Japanese';
      case 'ko':
        return 'Korean';
      default:
        return 'Unknown';
    }
  }

  String getColorName(Color color) {
    // colorMap의 value 중 일치하는 Color가 있는지 확인
    String colorKey = colorMap.entries
        .firstWhere((entry) => entry.value == color,
            orElse: () => MapEntry('white', Colors.white))
        .key;
    return colorKey;
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      await Permission.microphone.request();
      print("******* 녹음 권한 받음 *******");
    }
  }

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initializeMemoData();
    _initRecorder();
    _videoControllers = [];
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    String text = _controller.text;
    List<String> lines = text.split('\n');

    // 요약 추천 로직
    if (lines.length > 10 && !_shouldShowSummaryRecommendation) {
      setState(() {
        _shouldShowSummaryRecommendation = true;
      });
    } else if (lines.length <= 10 && _shouldShowSummaryRecommendation) {
      setState(() {
        _shouldShowSummaryRecommendation = false;
      });
    }

    for (String line in lines) {
      if (_isEventLine(line)) {
        _showEventConfirmationDialog(line);
        break;
      }
    }
  }

  void _checkAndRecommendSummary() {
    int characterCount = _controller.text.length;

    if (characterCount >= 300 && !_shouldShowSummaryRecommendation) {
      setState(() {
        _shouldShowSummaryRecommendation = true;
      });
    } else if (characterCount < 300 && _shouldShowSummaryRecommendation) {
      setState(() {
        _shouldShowSummaryRecommendation = false;
      });
    }
  }

  bool _isEventLine(String line) {
    RegExp pattern = RegExp(r'(\d{1,2})월 (\d{1,2})일\s+(.+)');
    return pattern.hasMatch(line);
  }

  void _showEventConfirmationDialog(String line) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('일정 추가 확인'),
          content: Text('이 내용을 캘린더에 추가하시겠습니까?\n$line'),
          actions: <Widget>[
            TextButton(
              child: Text('취소'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('추가'),
              onPressed: () {
                Navigator.of(context).pop();
                _processEventLine(line);
              },
            ),
          ],
        );
      },
    );
  }

  void _processEventLine(String line) {
    RegExp pattern = RegExp(r'(\d{1,2})월 (\d{1,2})일\s+(.+)');
    Match? match = pattern.firstMatch(line);

    if (match != null) {
      int month = int.parse(match.group(1)!);
      int day = int.parse(match.group(2)!);
      String eventDescription = match.group(3)!;

      // 연도를 2024로 고정
      DateTime eventDate = DateTime(2024, month, day);

      // 캘린더에 이벤트 추가
      CalendarScreen.addEvent(context, eventDate, eventDescription);
    }
  }

  Future<void> _initializeMemoData() async {
    if (widget.initialMemoId != null) {
      await _fetchMemoDetails(widget.initialMemoId!);
      // 초기 상태 저장
      _initialText = _controller.text;
      _initialBackgroundColor = _backgroundColor;
      _initialMediaPaths = List.from(_mediaPaths);

      if (widget.initialColor != null) {
        _backgroundColor = widget.initialColor!;
      }
      if (widget.initialImageData != null) {
        print('이미지 데이터 있음');
        _isMediaSelected = true;
        _fetchedImages.add(widget.initialImageData!);
      }
    }
    setState(() {
      _isLoading = false; // 로딩 상태 업데이트
    });
  }

  Future<void> _fetchMemoDetails(String memoId) async {
    final url = Uri.parse('$SERVER_IP/memo/$memoId/data');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> memoData = json.decode(response.body);

        for (var item in memoData) {
          if (item['format'] == 'txt') {
            final text = await _getData(item['data_id']);
            setState(() {
              _controller.text = text ?? '';
            });
          } else if (item['format'] == 'MOV' || item['format'] == 'mp4') {
            final videoPath = await _getVideo(item['data_id']);
            if (videoPath != null) {
              setState(() {
                _mediaPaths.add(videoPath);
                _initializeVideoController(videoPath, _mediaPaths.length - 1);
                _isMediaSelected = true;
              });
            }
          } else if (item['format'] == 'png' ||
              item['format'] == 'jpg' ||
              item['format'] == 'jpeg') {
            final imageData = await _getImage(item['data_id']);
            if (imageData != null) {
              // Save the image to a temporary file and add to _mediaPaths
              final tempFile = await _saveImageToFile(imageData);
              setState(() {
                _mediaPaths.add(tempFile.path);
                _isMediaSelected = true;
              });
            }
          } else {
            // 파일 포맷이 텍스트, 비디오, 이미지, 오디오가 아닌 경우
            final fileData = await _getFile(item['data_id']);
            if (fileData != null) {
              final directory = await getApplicationDocumentsDirectory();
              final filePath = '${directory.path}/${item['file_name']}';
              final file = File(filePath);
              await file.writeAsBytes(fileData);
              setState(() {
                _filePaths.add(file.path);
              });
            }
          }
        }
      } else {
        print('Failed to load memo data: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memo data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<File> _saveImageToFile(Uint8List imageData) async {
    final directory = await getTemporaryDirectory();
    final imagePath =
        '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.png';
    final imageFile = File(imagePath);
    return await imageFile.writeAsBytes(imageData);
  }

  Future<String?> _getVideo(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        // 서버로부터 받은 비디오 파일을 로컬에 저장한 후 경로를 반환
        final directory = await getTemporaryDirectory();
        final videoPath =
            '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';
        final videoFile = File(videoPath);
        await videoFile.writeAsBytes(response.bodyBytes);
        return videoPath;
      } else {
        print('Failed to load video: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('비디오 불러오기 실패: $e');
      return null;
    }
  }

  Future<String?> _getData(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      } else {
        print('파일 불러오기 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('파일 불러오기 실패!!: $e');
      return null;
    }
  }

  Future<Uint8List?> _getImage(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Failed to load image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('이미지 불러오기 실패: $e');
      return null;
    }
  }

  Future<Uint8List?> _getFile(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Failed to load file: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Failed to load file: $e');
      return null;
    }
  }

  Future<void> _getSummary() async {
    final response = await http.post(
      Uri.parse('$SERVER_IP/summarize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': _controller.text}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _summary = data['summary'];
      });
    } else {
      setState(() {
        _summary = '요약을 가져오는 중 오류 발생.';
      });
    }
  }

  Future<String> translateText(String text, String targetLanguage) async {
    final url =
        'https://translation.googleapis.com/language/translate/v2?key=$apiKey';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'target': targetLanguage,
        }),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}'); // 확인용

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translations = data['data']['translations'];
        if (translations != null && translations.isNotEmpty) {
          return translations[0]['translatedText'];
        } else {
          return 'No translation available';
        }
      } else {
        throw Exception('Failed to translate text');
      }
    } catch (e) {
      print('Error occurred: $e');
      throw Exception('Failed to translate text');
    }
  }

  Future<void> _translate() async {
    final textToTranslate = _controller.text; // 현재 사용 중인 컨트롤러

    if (textToTranslate.isEmpty) {
      setState(() {
        _translatedText = 'No text to translate';
      });
      return;
    }

    try {
      final translatedText =
          await translateText(textToTranslate, _selectedLanguage);
      setState(() {
        _translatedText = translatedText;
      });
    } catch (e) {
      print('Error occurred: $e');
      setState(() {
        _translatedText = 'Failed to translate text';
      });
    }
  }

  Future<String> convertM4aToWav(String m4aFilePath) async {
    try {
      // 출력될 wav 파일의 경로를 설정합니다.
      final directory = await getTemporaryDirectory();
      final wavFilePath =
          '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.wav';

      // FFmpeg 명령어를 사용하여 m4a를 모노 wav로 변환합니다.
      final arguments = ['-i', m4aFilePath, '-ac', '1', wavFilePath];

      final int result = await _flutterFFmpeg.executeWithArguments(arguments);

      if (result == 0) {
        print('Conversion successful');
        return wavFilePath; // 변환된 wav 파일의 경로를 반환합니다.
      } else {
        print('Conversion failed with result $result');
        throw Exception('Failed to convert m4a to wav');
      }
    } catch (e) {
      print('Error occurred: $e');
      throw Exception('Failed to convert m4a to wav');
    }
  }

  Future<void> _transcribeM4aFile(String m4aFilePath) async {
    try {
      final wavFilePath = await convertM4aToWav(m4aFilePath);
      await _transcribeAudio(wavFilePath);
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> _transcribeAudio(String filePath) async {
    final url = 'https://speech.googleapis.com/v1/speech:recognize?key=$apiKey';

    try {
      // 오디오 파일을 base64로 인코딩
      final bytes = File(filePath).readAsBytesSync();
      final audioContent = base64Encode(bytes);

      // Google Cloud Speech-to-Text API 요청 설정
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'config': {
            'encoding': 'LINEAR16',
            'sampleRateHertz': 44100,
            'languageCode': 'ko-KR', // 언어 코드 설정
          },
          'audio': {
            'content': audioContent,
          },
        }),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'];
        if (results != null && results.isNotEmpty) {
          final transcription = results[0]['alternatives'][0]['transcript'];
          setState(() {
            _transcription = transcription ?? 'No transcription available';
          });
        } else {
          setState(() {
            _transcription = 'No transcription available';
          });
        }
      } else {
        throw Exception('Failed to transcribe audio');
      }
    } catch (e) {
      print('Error occurred: $e');
      setState(() {
        _transcription = 'Failed to transcribe audio';
      });
    }
  }

  Future<void> _deleteMemoFromServer(String memoId) async {
    if (memoId == null) return;

    final url = Uri.parse('$SERVER_IP/memo/$memoId');
    final response = await http.delete(url);

    if (response.statusCode == 200) {
      print('메모 삭제 성공');
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
    }
  }

  Future<void> _initRecorder() async {
    await _recorder.isEncoderSupported(AudioEncoder.aacLc);
  }

  @override
  void dispose() {
    _recorder.dispose();
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _videoControllers.forEach((controller) {
      controller?.dispose();
    });
    super.dispose();
  }

  static String _generateRandomId() {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        16, (_) => characters.codeUnitAt(random.nextInt(characters.length))));
  }

  bool _hasMemoChanged() {
    if (_controller.text != _initialText) return true;
    if (_backgroundColor != widget.initialColor!) return true;
    if (_mediaPaths.length != _initialMediaPaths.length) return true;
    for (int i = 0; i < _mediaPaths.length; i++) {
      if (_mediaPaths[i] != _initialMediaPaths[i]) return true;
    }
    return false;
  }

  Future<void> _saveMemoToServer() async {
    if (!_hasMemoChanged()) {
      print('메모가 변경되지 않았습니다. 저장을 건너뜁니다.');
      return;
    }

    widget.initialMemoId ??= _generateRandomId();

    var url = Uri.parse('$SERVER_IP/memo');
    var request = http.MultipartRequest('POST', url);

    request.fields['userId'] = USER_ID;
    request.fields['isOpen'] = '1'; // Assuming the memo is public
    request.fields['theme'] =
        getColorName(_backgroundColor); // Color를 key로 변환하여 저장
    request.fields['posX'] = '100'; // Example position and size
    request.fields['posY'] = '100';
    request.fields['width'] = '400';
    request.fields['height'] = '300';
    request.fields['memo_id'] = widget.initialMemoId!;

    if (_controller.text.isNotEmpty) {
      request.fields['data_txt'] = _controller.text;
    } else {
      request.fields['data_txt'] = "";
    }

    print(_mediaPaths);
    // Add user-selected media files
    for (var filePath in _mediaPaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    // Convert fetched images to files and add them to the request
    // for (var imageData in _fetchedImages) {
    //   final imageFile = await _saveImageToFile(imageData);
    //   request.files
    //       .add(await http.MultipartFile.fromPath('files', imageFile.path));
    // }

    for (var filePath in _filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    if (widget.initialMemoId != null && _hasMemoChanged()) {
      await _deleteMemoFromServer(widget.initialMemoId!);
    }

    var response = await request.send();
    if (response.statusCode == 201) {
      print('메모 저장 성공');
      // 초기 상태를 현재 상태로 업데이트
      _initialText = _controller.text;
      _initialBackgroundColor = _backgroundColor;
      _initialMediaPaths = List.from(_mediaPaths);
    } else {
      print('메모 저장 실패: ${response.statusCode}');
    }
  }

  void _pickImageOrFile() async {
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
    try {
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
      }).catchError((error) {
        print("Video initialization failed: $error");
      });
    } catch (e) {
      print("Error initializing video: $e");
    }
  }

  // 녹음 시작
  Future<void> _startRecording() async {
    // var status = await Permission.microphone.status;
    // if (!status.isGranted) {
    //   status = await Permission.microphone.request();
    //   if (!status.isGranted) {
    //     // 권한이 부여되지 않았으므로, 녹음을 시작하지 않음.
    //     print("Microphone permission not granted");
    //     return;
    //   }
    // }
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String filePath =
        '${appDocDir.path}/memo_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      path: filePath,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      samplingRate: 44100,
    );
    setState(() {
      _isRecording = true;
      _audioPath = filePath;
    });
  }

  // 녹음 중지
  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
    });

    _mediaPaths.add(_audioPath!);
    if (_audioPath != null) {
      _transcribeM4aFile(_audioPath!);
    }
  }

  Future<void> _saveAndShareMemo() async {
    // 메모 저장은 이제 dialog에서 '전송' 버튼을 눌렀을 때 수행됩니다.
    _showFriendSelectionDialog();
  }

  Future<void> _shareMemoWithFriends(List<String> friendUserIds) async {
    try {
      // 먼저 메모를 서버에 저장합니다.
      await _saveMemoToServer();

      // 친구들에게 메모를 공유합니다.
      for (String friendUserId in friendUserIds) {
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

        if (response.statusCode != 200) {
          print('메모 공유 실패: ${response.statusCode}');
          _showMessage('메모 공유에 실패했습니다.');
          return;
        }
      }

      print('메모 공유 성공');
      _showMessage('메모가 성공적으로 공유되었습니다.');

      // 홈 화면으로 이동
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      // 오류 발생 시 메시지 표시
      _showMessage('메모 저장 또는 공유 중 오류가 발생했습니다.');
    }
  }

  Future<void> _showFriendSelectionDialog() async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, String>> friends = data
          .map<Map<String, String>>((friend) => {
                'user_name': friend['friend_name_set'],
                'user_id': friend['friend_id'],
              })
          .toList();

      List<String> selectedFriendIds = []; // 선택된 친구 ID를 저장하는 리스트

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('친구 선택'),
                content: Container(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      return CheckboxListTile(
                        title: Text(friends[index]['user_name']!),
                        value: selectedFriendIds
                            .contains(friends[index]['user_id']),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              selectedFriendIds.add(friends[index]['user_id']!);
                            } else {
                              selectedFriendIds
                                  .remove(friends[index]['user_id']);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 팝업 닫기
                    },
                    child: Text('취소'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 팝업 닫기
                      _shareMemoWithFriends(
                          selectedFriendIds); // 메모 저장 후 공유 및 홈 화면으로 이동
                    },
                    child: Text('전송'),
                  ),
                ],
              );
            },
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
        if (index < _videoControllers.length &&
            _videoControllers[index] != null &&
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
        if (index < _mediaPaths.length &&
            (_mediaPaths[index].endsWith('.mp4') ||
                _mediaPaths[index].endsWith('.MOV') ||
                _mediaPaths[index].endsWith('.mov'))) {
          if (index >= _videoControllers.length) {
            // _videoControllers 리스트 크기보다 큰 인덱스가 필요할 경우, null로 채워넣기
            for (int i = _videoControllers.length; i <= index; i++) {
              _videoControllers.add(null);
            }
          }
          if (_videoControllers[index] == null) {
            _initializeVideoController(_mediaPaths[index], index);
          } else if (!_videoControllers[index]!.value.isPlaying) {
            _videoControllers[index]!.play();
          }
        }
      }
    });
  }

  // 파일 아이템 UI
  Widget _buildFileTile(String filePath) {
    final fileName = filePath.split('/').last;
    final isPdf = filePath.endsWith('.pdf');

    return GestureDetector(
      onTap: () {
        if (isPdf) {
          // PDF 파일도 MediaViewer로 이동
          _openMediaViewer(filePath);
        } else {
          _downloadFile(filePath, fileName);
        }
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8.0),
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(58.0),
        ),
        child: Row(
          children: [
            Icon(isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                color: isPdf ? Colors.red : Colors.grey[700]), // PDF 파일 아이콘
            SizedBox(width: 16.0),
            Expanded(
              child: Text(
                fileName,
                style: TextStyle(color: Colors.black, fontSize: 16.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.download, color: Colors.grey),
              onPressed: () => _downloadFile(filePath, fileName),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(String filePath, String fileName) async {
    try {
      String savePath;

      // 플랫폼에 따라 저장 경로를 다르게 설정
      if (Platform.isAndroid) {
        // Android의 'Downloads' 폴더 경로 가져오기
        final directory = await getExternalStorageDirectory();
        savePath = '${directory!.path}/$fileName';
      } else if (Platform.isIOS) {
        // iOS의 'Documents' 폴더 경로 가져오기
        final directory = await getApplicationDocumentsDirectory();
        savePath = '${directory.path}/$fileName';
      } else {
        // Web 또는 다른 플랫폼은 지원되지 않음
        throw UnsupportedError('Unsupported platform');
      }

      print("파일 저장 경로 $savePath");

      // 파일 데이터를 가져와서 로컬에 저장
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final localFile = File(savePath);
        await localFile.writeAsBytes(bytes);

        _showMessage('파일이 성공적으로 다운로드되었습니다: $savePath');
      } else {
        _showMessage('파일이 존재하지 않습니다.');
      }
    } catch (e) {
      _showMessage('파일 다운로드 중 오류 발생: $e');
    }
  }

  Future<void> _openMediaViewer(String filePath) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaViewer(
          filePath: filePath,
          onDelete: () {
            setState(() {
              _filePaths.remove(filePath);
            });
          },
        ),
      ),
    );
  }

  // 이 함수는 _buildMediaTile에서도 사용됩니다.
  Widget _buildMediaTile(String filePath, int index) {
    final isVideo = filePath.endsWith('.mp4') ||
        filePath.endsWith('.MOV') ||
        filePath.endsWith('.mov');
    final isAudio = filePath.endsWith('.m4a') || filePath.endsWith('.aac');
    final isPdf = filePath.endsWith('.pdf');

    return GestureDetector(
      onTap: () {
        _openMediaViewer(filePath);
      },
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    border: Border.all(
                      color: isAudio ? Colors.blue : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                  child: isVideo
                      ? _videoControllers[index] != null &&
                              _videoControllers[index]!.value.isInitialized
                          ? VideoPlayer(_videoControllers[index]!)
                          : Center(child: CircularProgressIndicator())
                      : isAudio
                          ? Icon(Icons.audiotrack,
                              size: 50, color: Colors.black)
                          : isPdf
                              ? Icon(Icons.picture_as_pdf,
                                  size: 50, color: Colors.red)
                              : Image.file(File(filePath), fit: BoxFit.cover),
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
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      onPopInvoked: (isGesture) {
        _saveMemoToServer(); // 서버에 메모를 저장하는 동작을 수행합니다.
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Color(0xFFFFE996),
        appBar: AppBar(
          backgroundColor: Color(0xFFFFE996),
          leading: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: BackButton(
              color: Colors.black,
              onPressed: () async {
                await _saveMemoToServer();
                Navigator.pop(context, {
                  'text': _controller.text,
                  'color': _backgroundColor,
                  'memo_id': widget.initialMemoId,
                });
              },
            ),
          ),
          title: Text('메모 작성', style: TextStyle(color: Colors.black)),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Wrap(
                spacing: 16.0, // 버튼 간의 간격을 일정하게 유지
                children: <Widget>[
                  IconButton(
                    iconSize: 30.0,
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickImageOrFile,
                  ),
                  IconButton(
                    iconSize: 30.0,
                    icon: _isRecording
                        ? Icon(Icons.stop, color: Colors.red)
                        : Icon(CupertinoIcons.mic),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                  ),
                  IconButton(
                    iconSize: 30.0,
                    icon: const Icon(Icons.edit_note),
                    onPressed: _getSummary,
                  ),
                  IconButton(
                    iconSize: 30.0,
                    icon: const Icon(Icons.translate),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (BuildContext context) {
                          return Container(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _languages.map((String language) {
                                return ListTile(
                                  title: Text(_getLanguageName(language)),
                                  onTap: () {
                                    setState(() {
                                      _selectedLanguage = language;
                                    });
                                    Navigator.pop(context); // 메뉴를 닫음
                                    _translate(); // 번역 실행
                                  },
                                );
                              }).toList(),
                            ),
                          );
                        },
                      );
                    },
                    tooltip: 'Translate Text',
                  ),
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
        body: _isLoading
            ? Center(child: CircularProgressIndicator()) // 로딩 중일 때는 로딩 인디케이터 표시
            : GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus(); // 키보드 내리기
                },
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(height: 10.0),
                      Image.asset(
                        'assets/images/img_quickduck.png',
                        height: 80,
                      ),
                      SizedBox(height: 25.0),
                      Container(
                        width: screenWidth * 0.9,
                        height: screenHeight * 0.5,
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
                            if (_mediaPaths.isNotEmpty ||
                                _fetchedImages.isNotEmpty)
                              Expanded(
                                flex: 5,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount:
                                      _mediaPaths.length, // 미디어 리스트 수 만큼 표시
                                  itemBuilder: (context, index) {
                                    return _buildMediaTile(
                                        _mediaPaths[index], index);
                                  },
                                ),
                              ),
                            if (_filePaths.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  children: _filePaths
                                      .map((filePath) =>
                                          _buildFileTile(filePath))
                                      .toList(),
                                ),
                              ),
                            Expanded(
                              flex: 5,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: _isMediaSelected && _imageData != null
                                    ? Container(
                                        constraints: BoxConstraints(
                                          maxWidth: screenWidth *
                                              0.9, // 이미지의 최대 너비를 제한
                                          maxHeight: screenHeight *
                                              0.4, // 이미지의 최대 높이를 제한
                                        ),
                                        child: Image.memory(
                                          _imageData!,
                                          fit: BoxFit.contain, // 이미지를 원래 비율로 맞춤
                                        ),
                                      )
                                    : TextField(
                                        controller: _controller,
                                        maxLines: null,
                                        focusNode: _focusNode,
                                        onChanged: (text) {
                                          _checkAndRecommendSummary(); // 텍스트가 변경될 때마다 요약 추천 체크
                                        },
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          hintText: '메모를 입력하세요...',
                                        ),
                                        style: TextStyle(
                                          fontSize: 16.0,
                                          color: Colors.black,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_shouldShowSummaryRecommendation)
                        Container(
                          width: screenWidth * 0.9,
                          padding: EdgeInsets.all(16.0),
                          margin: EdgeInsets.only(top: 10.0),
                          decoration: BoxDecoration(
                            color: Colors.yellow[100],
                            borderRadius: BorderRadius.circular(16.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8.0,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '텍스트가 길어졌네요! 요약을 해보시겠어요?',
                                style: TextStyle(
                                    fontSize: 16.0, color: Colors.black),
                              ),
                              TextButton(
                                onPressed: _getSummary,
                                child: Text(
                                  '요약하기',
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_summary.isNotEmpty) // _summary 내용이 있을 때만 표시
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
                          child: Text(
                            _summary,
                            style:
                                TextStyle(fontSize: 16.0, color: Colors.black),
                          ),
                        ),
                      if (_transcription.isNotEmpty) // 트랜스크립션 내용이 있을 때만 표시
                        SizedBox(height: 20.0),
                      if (_transcription.isNotEmpty)
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
                          child: Text(
                            _transcription,
                            style:
                                TextStyle(fontSize: 16.0, color: Colors.black),
                          ),
                        ),
                      if (_translatedText.isNotEmpty) SizedBox(height: 20.0),
                      if (_translatedText.isNotEmpty)
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
                          child: Text(
                            _translatedText,
                            style:
                                TextStyle(fontSize: 16.0, color: Colors.black),
                          ),
                        ),
                      SizedBox(height: 40.0),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          color: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Container(
                            width: MediaQuery.of(context).size.width,
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
                                      margin:
                                          EdgeInsets.symmetric(horizontal: 10),
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: entry.value,
                                        borderRadius:
                                            BorderRadius.circular(20.0),
                                        border: Border.all(
                                          color: _backgroundColor == entry.value
                                              ? Colors.black
                                              : Colors.transparent,
                                          width: 2.0,
                                        ),
                                      ),
                                      child: Center(
                                        child: _backgroundColor == entry.value
                                            ? Icon(Icons.check,
                                                color: Colors.black)
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
      ),
    );
  }
}
