import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../../../globals.dart';
import '../calendar/calendar_screen.dart';
import 'media_viewer.dart';
import 'package:intl/intl.dart';

class WriteMemoScreen extends StatefulWidget {
  final Color? initialColor;
  String? initialMemoId;
  final Uint8List? initialImageData;
  int? isRead;

  WriteMemoScreen({
    this.initialColor,
    this.initialMemoId,
    this.initialImageData,
    this.isRead,
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
  bool _shouldShowTranslationRecommendation = false;
  Timer? _debounce; // 타이머를 관리할 변수 추가
  RichText? _richText;

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

    print(widget.isRead);
  }

  Set<String> _currentDetectedLanguages = {}; // 감지된 언어를 저장하는 Set

  Future<void> _handleTextChanged() async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      String text = _controller.text;

      Set<String> allDetectedLanguages = {}; // 전체 감지된 언어를 저장할 Set

      // 요약 추천 로직 (100자 이상 입력 시)
      if (text.length >= 100 && !_shouldShowSummaryRecommendation) {
        setState(() {
          _shouldShowSummaryRecommendation = true;
        });
      } else if (text.length < 100 && _shouldShowSummaryRecommendation) {
        setState(() {
          _shouldShowSummaryRecommendation = false;
        });
      }

      if (text.isNotEmpty) {
        // 새로 입력된 텍스트에 대한 언어 감지
        final detectedLanguages = await _detectLanguages(text);

        // 감지된 언어를 기존에 감지된 언어와 합치기
        _currentDetectedLanguages.addAll(detectedLanguages);

        print(
            'Current detected languages: $_currentDetectedLanguages'); // 감지된 전체 언어 확인

        // 여러 언어가 섞여 있으면 번역 버튼 표시
        if (_currentDetectedLanguages.contains('ko') &&
            _currentDetectedLanguages.length > 1) {
          setState(() {
            _shouldShowTranslationRecommendation = true;
          });
        } else if (!_currentDetectedLanguages.contains('ko') &&
            _currentDetectedLanguages.isNotEmpty) {
          setState(() {
            _shouldShowTranslationRecommendation = true;
          });
        } else {
          setState(() {
            _shouldShowTranslationRecommendation = false;
          });
        }
      } else {
        // 텍스트가 비었을 때 번역 버튼 숨기기
        setState(() {
          _shouldShowTranslationRecommendation = false;
        });

        // 텍스트가 비면 감지된 언어 초기화
        _currentDetectedLanguages.clear();
      }

      // URL 감지 및 하이퍼링크 처리
      _handleUrlDetection(text);
    });
  }

  void _handleUrlDetection(String text) {
    final RegExp urlRegExp = RegExp(r'(https?://\S+)');
    List<TextSpan> spans = [];
    int start = 0;

    for (Match match in urlRegExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: TextStyle(color: Colors.black),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style:
            TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _launchURL(match.group(0)!),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(color: Colors.black),
      ));
    }

    setState(() {
      _richText = RichText(
        text: TextSpan(children: spans),
      );
    });
  }

  Future<void> _launchURL(String url) async {
    Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<Set<String>> _detectLanguages(String text) async {
    final url =
        'https://translation.googleapis.com/language/translate/v2/detect?key=$apiKey';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'q': text}),
      );

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final detections = data['data']['detections'];
        final Set<String> detectedLanguages = {};

        if (detections != null && detections.isNotEmpty) {
          for (var detection in detections) {
            for (var langData in detection) {
              detectedLanguages.add(langData['language']);
            }
          }
        }
        print('Detected languages: $detectedLanguages');
        return detectedLanguages;
      } else {
        throw Exception('Failed to detect languages');
      }
    } catch (e) {
      print('Error occurred: $e');
      return {'und'}; // 감지되지 않음
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
          } else if (item['format'] == 'm4a' || item['format'] == 'aac') {
            final audioPath = await _getAudio(item['data_id']);
            if (audioPath != null) {
              setState(() {
                _mediaPaths.add(audioPath);
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

  Future<String?> _getAudio(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        // 서버로부터 받은 오디오 파일을 로컬에 저장한 후 경로를 반환
        final directory = await getTemporaryDirectory();
        final audioPath =
            '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
        final audioFile = File(audioPath);
        await audioFile.writeAsBytes(response.bodyBytes);
        return audioPath;
      } else {
        print('Failed to load audio: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('오디오 불러오기 실패: $e');
      return null;
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
    final url = 'https://api.openai.com/v1/chat/completions';

    // 메시지 배열을 설정하여 요약 요청
    final messages = [
      {
        'role': 'system',
        'content': 'You are a helpful assistant who summarizes text.'
      },
      {'role': 'user', 'content': _controller.text}
    ];

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openapiKey',
          'Accept-Charset': 'UTF-8', // UTF-8 인코딩 요청
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 100, // 요약 길이 조정
          'temperature': 0.7, // 생성 다양성 조정
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('Raw response body: $responseBody'); // 응답 본문 출력

        final data = jsonDecode(response.body);
        final summary = data['choices'][0]['message']['content'].trim();
        setState(() {
          _summary = summary;
        });
      } else {
        setState(() {
          _summary = '요약을 가져오는 중 오류 발생.';
        });
      }
    } catch (e) {
      print('Error occurred: $e');
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
          'q': text, // 번역할 텍스트
          'target': targetLanguage, // 타겟 언어 (예: 'ko')
          'source': 'en', // 소스 언어 (예: 'en'으로 설정)
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
      // 번역할 언어를 한국어로 설정 (고정값으로 설정)
      final translatedText = await translateText(textToTranslate, 'ko');
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
    _debounce?.cancel(); // 타이머가 있으면 취소
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
    // 텍스트가 없고, 미디어와 파일도 없는 경우 저장하지 않음
    if (_controller.text.isEmpty && _mediaPaths.isEmpty && _filePaths.isEmpty) {
      print('저장할 내용이 없습니다. 저장을 건너뜁니다.');
      return;
    }

    // 메모 변경 확인
    if (widget.isRead == 1 && !_hasMemoChanged()) {
      print('메모가 변경되지 않았습니다. 저장을 건너뜁니다.');
      return;
    }

    // 메모 ID가 없으면 새로 생성
    widget.initialMemoId ??= _generateRandomId(); // 랜덤 메모 ID 생성
    String generatedTitle = generateTitle(_controller.text.isEmpty
        ? '미디어 메모' // 텍스트가 없을 경우 기본 제목 설정
        : _controller.text);
    print('메모 제목: $generatedTitle');

    var url = Uri.parse('$SERVER_IP/memo');
    var request = http.MultipartRequest('POST', url);

    // 필수 필드 추가
    request.fields['userId'] = USER_ID;
    request.fields['theme'] =
        getColorName(_backgroundColor); // Color를 key로 변환하여 저장
    request.fields['posX'] = '100'; // 위치, 크기 예시
    request.fields['posY'] = '100';
    request.fields['width'] = '400';
    request.fields['height'] = '300';
    request.fields['memo_id'] = widget.initialMemoId!;
    request.fields['title'] = generatedTitle;
    request.fields['is_read'] = 1.toString(); // 읽음 안읽음 여부 판단
    request.fields['sender_user_id'] = USER_ID;

    // 텍스트가 있는 경우 추가, 없으면 빈 텍스트로 추가
    request.fields['data_txt'] =
        _controller.text.isNotEmpty ? _controller.text : "";

    // 미디어 파일 추가
    for (var filePath in _mediaPaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    // 이미지 파일 추가
    for (var imageData in _fetchedImages) {
      final imageFile = await _saveImageToFile(imageData);
      request.files
          .add(await http.MultipartFile.fromPath('files', imageFile.path));
    }

    // 기타 파일 추가
    for (var filePath in _filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    // 기존 메모가 있으면 삭제
    if (widget.initialMemoId != null) {
      await _deleteMemoFromServer(widget.initialMemoId!);
    }

    // 메모 저장 요청 보내기
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

  bool _isEventLine(String line) {
    // 여러 이벤트를 처리할 수 있도록 정규식 수정
    RegExp pattern =
        RegExp(r'^(1[0-2]|[1-9])[월./] ?(\d{1,2})[일]? ?(.+)$', multiLine: true);
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
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            TextButton(
              child: Text('추가'),
              onPressed: () async {
                Navigator.of(context).pop();
                _processEventLine(line); // 비동기 함수 호출
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        );
      },
    );
  }

  void _processEventLine(String line) async {
    // 여러 이벤트를 인식하도록 정규식을 사용하여 모든 매치 찾기
    RegExp pattern = RegExp(
        r'(\d{1,2})월 (\d{1,2})일(?:\s+(\d{1,2}):(\d{1,2}))?\s+(.+?)(?=\s+\d{1,2}월|\Z)');
    Iterable<Match> matches = pattern.allMatches(line);

    if (matches.isNotEmpty) {
      for (Match match in matches) {
        int month = int.parse(match.group(1)!);
        int day = int.parse(match.group(2)!);
        int hour = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        int minute = match.group(4) != null ? int.parse(match.group(4)!) : 0;
        String eventDescription = match.group(5)!;

        // 연도를 2024로 고정
        DateTime eventDate = DateTime(2024, month, day, hour, minute);

        // 이벤트 날짜와 시간을 적절한 형식으로 변환 (입력된 시간이 없는 경우 00:00:00)
        String eventDateTimeString =
            DateFormat('yyyy-MM-dd HH:mm:ss').format(eventDate);

        // 서버로 보낼 데이터를 JSON으로 변환
        Map<String, String> eventData = {
          'user_id': USER_ID,
          'event_datetime': eventDateTimeString,
          'description': eventDescription,
        };

        // HTTP POST 요청
        try {
          var response = await http.post(
            Uri.parse('$SERVER_IP/events'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(eventData),
          );

          if (response.statusCode == 200) {
            print('Event added successfully: ${response.body}');
          } else {
            print('Failed to add event: ${response.statusCode}');
          }
        } catch (e) {
          print('Error occurred: $e');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('일정 형식이 올바르지 않습니다.')),
      );
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
      while (_videoControllers.length <= index) {
        _videoControllers.add(null);
      }

      final controller = VideoPlayerController.file(File(videoPath));

      controller.initialize().then((_) {
        setState(() {
          _videoControllers[index] = controller;
          _videoControllers[index]?.play(); // Auto-play the video
        });
      }).catchError((error) {
        print("Video initialization failed: $error");
      });
    } catch (e) {
      print("Error initializing video: $e");
    }
  }

  void _extractAndLinkifyText(BuildContext context) {
    final text = _controller.text;
    final datePattern = RegExp(
        r'(\d{1,4})[.-](\d{1,2})[.-](\d{1,2})|(\d{1,2})[월.]?\s*(\d{1,2})[일]?');
    final matches = datePattern.allMatches(text);

    final events = <DateTime, String>{};
    int lastIndex = 0;
    DateTime? lastDate;

    for (final match in matches) {
      DateTime? date;

      if (match.group(1) != null) {
        // yyyy-mm-dd, yy-m-d 형식
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);

        date = DateTime(
          year < 100 ? (year + 2000) : year, // 2자리 연도 처리
          month,
          day,
        );
      } else if (match.group(4) != null) {
        // "7월 14일" 형식
        final month = int.parse(match.group(4)!);
        final day = int.parse(match.group(5)!);

        final currentYear = DateTime.now().year;
        date = DateTime(currentYear, month, day);
      }

      if (date != null) {
        final content = text.substring(lastIndex, match.start).trim();
        lastIndex = match.end;

        if (content.isNotEmpty) {
          events[date] = content;
        }

        lastDate = date; // 마지막 날짜 업데이트
      }
    }

    // 마지막 날짜 이후의 내용 추가
    if (lastIndex < text.length) {
      final content = text.substring(lastIndex).trim();
      if (content.isNotEmpty) {
        final eventDate = lastDate ?? DateTime.now(); // 마지막 날짜가 없으면 오늘 날짜로 설정
        events[eventDate] = content;
      }
    }

    // 날짜가 추가된 순서대로 정렬 후 다이얼로그 표시
    final sortedEvents = events.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedEvents.isNotEmpty) {
      for (var entry in sortedEvents) {
        _showAddEventDialog(context, entry.key, entry.value);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('날짜가 포함된 텍스트가 없습니다.')),
      );
    }
  }

  void _showAddEventDialog(BuildContext context, DateTime date, String text) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('일정을 추가할까요?'),
          content:
              Text('날짜: ${DateFormat('yyyy-MM-dd').format(date)}\n내용: $text'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('아니오'),
            ),
            TextButton(
              onPressed: () {
                // CalendarScreen.addEvent(context, date, text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('일정이 추가되었습니다.')),
                );
              },
              child: const Text('예'),
            ),
          ],
        );
      },
    );
  }

  // 녹음 시작
  Future<void> _startRecording() async {
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

    // 녹음이 완료된 후 다이얼로그 표시
    if (_audioPath != null) {
      _showTranscriptionDialog(_audioPath!);
    }
  }

  void _showTranscriptionDialog(String audioPath) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('음성 인식'),
          content: Text('음성 인식을 시작하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                _transcribeM4aFile(audioPath); // 트랜스크립션 수행
              },
              child: Text('확인'),
            ),
          ],
        );
      },
    );
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

  void _removeFile(int index) {
    setState(() {
      _filePaths.removeAt(index);
    });
  }

//   void _removeAudio(int index) {
//   setState(() {
//     // 오디오 플레이어가 있을 경우 정리합니다.
//     if (_audioPlayers.isNotEmpty && _audioPlayers.length > index && _audioPlayers[index] != null) {
//       _audioPlayers[index]?.dispose();
//       _audioPlayers.removeAt(index);
//     }

//     // 오디오 파일 경로를 리스트에서 제거합니다.
//     if (_audioPath.length > index) {
//       _audioPath.removeAt(index);
//     }

//     // 선택된 미디어 인덱스를 초기화합니다.
//     _selectedMediaIndex = null;
//   });
// }

  // 제목 생성 함수
  String generateTitle(String text) {
    if (text.trim().isEmpty) {
      return "제목 없음"; // 기본 제목 설정
    } else if (text.trim().length <= 15) {
      return text.trim();
    }

    List<String> keyPhrases = extractKeyPhrases(text);

    // 불용어 리스트를 정의합니다.
    List<String> stopWords = [
      "이",
      "그",
      "저",
      "은",
      "는",
      "이",
      "가",
      "을",
      "를",
      "에",
      "의",
      "과",
      "와"
    ];

    // 키워드에서 중요하지 않은 단어들을 제거하고 중요한 단어들을 조합하여 제목을 생성합니다.
    List<String> importantWords =
        keyPhrases.where((word) => !stopWords.contains(word)).take(3).toList();

    // 중요한 단어들을 조합하여 제목을 생성합니다.
    String title = importantWords.join(' ');

    // 제목이 비어 있거나 15자보다 길다면 15자까지 자릅니다.
    if (title.isEmpty || title.length > 15) {
      title = text.trim().substring(0, 15);
    }

    return title;
  }

  List<String> extractKeyPhrases(String text) {
    // 예시: 간단한 키워드 추출 (실제 로직은 더욱 복잡할 수 있습니다)
    List<String> words = text.split(RegExp(r'\s+'));
    List<String> keyPhrases = words.where((word) => word.length > 1).toList();

    return keyPhrases;
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
  Widget _buildFileTile(String filePath, int index, int realIndex) {
    final fileName = filePath.split('/').last;
    final isPdf = filePath.endsWith('.pdf');
    final isExcel = filePath.endsWith('.xls') || filePath.endsWith('.xlsx');
    final isPpt = filePath.endsWith('.ppt') || filePath.endsWith('.pptx');
    final isDocx = filePath.endsWith('.docx');
    final isHwp = filePath.endsWith('.hwp'); // 한글 파일 확장자

    IconData iconData;
    Color iconColor;

    if (isPdf) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (isExcel) {
      iconData = Icons.insert_chart; // Excel 파일 아이콘
      iconColor = Colors.green;
    } else if (isPpt) {
      iconData = Icons.slideshow; // PowerPoint 파일 아이콘
      iconColor = Colors.orange;
    } else if (isDocx) {
      iconData = Icons.description; // Word 파일 아이콘
      iconColor = Colors.blue;
    } else if (isHwp) {
      iconData = Icons.description; // 한글 파일 아이콘 (별도의 아이콘이 없으므로 기본 아이콘 사용)
      iconColor = Colors.lightBlue;
    } else {
      iconData = Icons.insert_drive_file; // 기본 파일 아이콘
      iconColor = Colors.grey;
    }

    return GestureDetector(
      onTap: () {
        OpenFile.open(filePath);
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8.0),
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            Icon(
              iconData,
              color: iconColor,
            ),
            SizedBox(width: 16.0),
            Expanded(
              child: Text(
                fileName,
                style: TextStyle(color: Colors.black, fontSize: 16.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 15.0),
            IconButton(
              icon: Icon(Icons.download, color: Colors.grey),
              onPressed: () => _downloadFile(filePath, fileName),
            ),
            IconButton(
              onPressed: () => _deleteFile(filePath, realIndex),
              icon: Icon(Icons.delete, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteFile(String filePath, int index) {
    setState(() {
      // 리스트의 길이와 인덱스가 일치하는지 확인
      if (index >= 0 && index < _filePaths.length) {
        _filePaths.removeAt(index); // 리스트에서 파일 경로 제거
      } else {
        print('Error: Index $index is out of range.');
      }
    });
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

  Future<void> _openMediaViewer(String filePath, int index, bool isFile) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaViewer(
          filePath: filePath,
          onDelete: () {
            setState(() {
              if (isFile) {
                _removeFile(index);
              } else {
                _removeMedia(index);
              }
            });
          },
        ),
      ),
    );

    // 'transcribe'가 반환된 경우 _transcribeM4aFile 함수 호출
    if (result == 'transcribe') {
      _transcribeM4aFile(filePath);
    }
  }

  // 이 함수는 _buildMediaTile에서도 사용됩니다.
  Widget _buildMediaTile(String filePath, int index) {
    final isVideo = filePath.endsWith('.mp4') ||
        filePath.endsWith('.MOV') ||
        filePath.endsWith('.mov');
    final isAudio = filePath.endsWith('.m4a') || filePath.endsWith('.aac');

    return GestureDetector(
      onTap: () {
        _openMediaViewer(filePath, index, false);
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
                      color: Colors.transparent,
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
      onPopInvoked: (bool value) async {
        await _saveMemoToServer();
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true, // 키보드에 의해 위젯이 가려지지 않도록 설정
        backgroundColor: Color(0xFFADDCFF), // #ADDCFF
        appBar: AppBar(
          backgroundColor: Color(0xFFADDCFF),
          leading: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: BackButton(
              color: Colors.black,
              onPressed: () async {
                await _saveMemoToServer();
                String currentText = _controller.text;

                if (_isEventLine(currentText)) {
                  // Show confirmation dialog if the input is a valid event line
                  _showEventConfirmationDialog(currentText);
                } else {
                  // If not a valid event line, navigate back immediately
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Wrap(
                spacing: 16.0, // 버튼 간의 간격을 일정하게 유지
                children: <Widget>[
                  if (_shouldShowSummaryRecommendation)
                    IconButton(
                        onPressed: _getSummary,
                        icon: Image.asset(
                          'assets/images/summary.png',
                          height: 40,
                        )),
                  if (_shouldShowTranslationRecommendation)
                    IconButton(
                        onPressed: _translate,
                        icon: Image.asset(
                          'assets/images/translate.png',
                          height: 40,
                        )),
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
                      SizedBox(
                        height: 30.0,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Image.asset(
                              'assets/images/insert_file.png',
                              height: 90,
                            ),
                            onPressed: _pickImageOrFile,
                          ),
                          IconButton(
                            iconSize: 30.0,
                            icon: _isRecording
                                ? Icon(Icons.stop, color: Colors.red)
                                : Image.asset(
                                    'assets/images/record_duck.png',
                                    height: 90,
                                  ),
                            onPressed:
                                _isRecording ? _stopRecording : _startRecording,
                          ),
                          IconButton(
                            iconSize: 30.0,
                            icon: Image.asset(
                              'assets/images/send_duck.png',
                              height: 90,
                            ),
                            onPressed: _saveAndShareMemo,
                          ),
                        ],
                      ),
                      SizedBox(height: 30.0),
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
                              SizedBox(
                                height: screenHeight * 0.25, // 미디어 영역의 높이 고정
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _mediaPaths.length,
                                  itemBuilder: (context, index) {
                                    return _buildMediaTile(
                                        _mediaPaths[index], index);
                                  },
                                ),
                              ),
                            if (_filePaths.isNotEmpty)
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.all(8.0),
                                  itemCount: _filePaths.length,
                                  itemBuilder: (context, index) {
                                    return _buildFileTile(_filePaths[index],
                                        index + _mediaPaths.length, index);
                                  },
                                ),
                              ),
                            if (_isMediaSelected && _imageData != null)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                constraints: BoxConstraints(
                                  maxWidth: screenWidth * 0.9,
                                  maxHeight: screenHeight * 0.4,
                                ),
                                child: Image.memory(
                                  _imageData!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            if (!_isMediaSelected || _imageData == null)
                              Expanded(
                                child: SingleChildScrollView(
                                  child: TextField(
                                    controller: _controller,
                                    maxLines: null,
                                    focusNode: _focusNode,
                                    onChanged: (text) {
                                      _handleTextChanged(); // 텍스트가 변경될 때마다 요약 추천 체크
                                    },
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: '메모를 입력하세요...',
                                      contentPadding: EdgeInsets.only(
                                          left: 16.0), // 왼쪽 여백 추가
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
                      if (_summary.isNotEmpty) // _summary 내용이 있을 때만 표시
                        SizedBox(height: 20.0),
                      if (_summary.isNotEmpty)
                        GestureDetector(
                          onDoubleTap: () {
                            Clipboard.setData(ClipboardData(text: _summary));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Summary 텍스트가 복사되었습니다!')),
                            );
                          },
                          child: Container(
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
                              style: TextStyle(
                                  fontSize: 16.0, color: Colors.black),
                            ),
                          ),
                        ),
                      if (_transcription.isNotEmpty) // 트랜스크립션 내용이 있을 때만 표시
                        SizedBox(height: 20.0),
                      if (_transcription.isNotEmpty)
                        GestureDetector(
                          onDoubleTap: () {
                            Clipboard.setData(
                                ClipboardData(text: _transcription));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Transcription 텍스트가 복사되었습니다!')),
                            );
                          },
                          child: Container(
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
                              style: TextStyle(
                                  fontSize: 16.0, color: Colors.black),
                            ),
                          ),
                        ),
                      if (_translatedText.isNotEmpty) SizedBox(height: 20.0),
                      if (_translatedText.isNotEmpty)
                        GestureDetector(
                          onDoubleTap: () {
                            Clipboard.setData(
                                ClipboardData(text: _translatedText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Translated 텍스트가 복사되었습니다!')),
                            );
                          },
                          child: Container(
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
                              style: TextStyle(
                                  fontSize: 16.0, color: Colors.black),
                            ),
                          ),
                        ),
                      SizedBox(height: 10.0),
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