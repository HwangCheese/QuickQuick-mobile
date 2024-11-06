import 'dart:async';
import 'dart:ui' as ui;

import 'package:docx_to_text/docx_to_text.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import '../../globals.dart';
import '../video_call/video_call_screen.dart';
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
  List<VideoPlayerController?> _videoControllers = [];
  String _summary = '';
  String _originalText = '';
  bool _isLoading = true; // 로딩 상태를 추가
  String _translatedText = '';
  String _selectedLanguage = 'ko';
  final String _textToProcess = '';
  bool _shouldShowSummaryRecommendation = false;
  final Record _recorder = Record();
  String _transcription = ''; // 트랜스크립션 결과를 저장할 변수
  bool _shouldShowTranslationRecommendation = false;
  bool _shouldShowVideoCallButton = false;
  bool _shouldShowClassificationButton = false;
  Timer? _debounce; // 타이머를 관리할 변수 추가
  List<String> _detectedUrls = [];
  List<Map<String, dynamic>> _classification = [];
  final ScrollController _textScrollController = ScrollController();
  Map<String, String> _placeInfoMap = {};
  List<String> _detectedDateLines = [];

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

  List<String> _detectedPlaces = [];

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

      List<String> urls = [];
      List<String> detectedMeetingTexts = []; // 감지된 화상회의 텍스트 저장 리스트

      // URL 정규 표현식
      RegExp urlRegExp = RegExp(
        r'(https?:\/\/[^\s]+)',
        caseSensitive: false,
        multiLine: true,
      );

      // 화상회의 텍스트 감지 정규식
      RegExp videoCallPattern =
      RegExp(r"(.+?)(랑|와|과)\s*(화상회의|회의|얘기|이야기|대화|통화)\s*");

      RegExp placePattern = RegExp(r'(.+?)에서');
      Match? match = placePattern.firstMatch(text);

      Iterable<RegExpMatch> urlMatches = urlRegExp.allMatches(text);
      Iterable<RegExpMatch> videoCallMatches =
      videoCallPattern.allMatches(text);

      // URL 추출
      for (RegExpMatch match in urlMatches) {
        String url = match.group(0)!;
        urls.add(url);
      }

      // 화상회의 텍스트 추출
      for (RegExpMatch match in videoCallMatches) {
        String meetingText = match.group(0)!;
        detectedMeetingTexts.add(meetingText);
      }

      setState(() {
        _detectedUrls = urls;
      });

      _detectedPlaces.clear();

      if (match != null) {
        String place = match.group(1)!.trim();
        // 장소 이름으로 검색 로직 수행
        _searchPlaceWithKakaoAPI(place);
      }

      // 일정 정보만 저장할 리스트 초기화
      List<String> detectedDateLines = [];

      // 텍스트를 줄 단위로 분리
      List<String> lines = text.split('\n');

      // 일정 정규 표현식
      RegExp datePattern = RegExp(
        r'(?:(\d{4})년\s*)?' + // 연도 (선택적)
            r'(?:(\d{1,2})[월./-]\s*)?' + // 월 (없을 수 있음)
            r'(?:(\d{1,2})(?:[일]?)?)' + // 일 (있어야 함)
            r'(?:\s*[~-]\s*(?:(\d{1,2})[월./-]\s*)?(?:(\d{1,2})[일]?)?)?\s*' + // ~ 또는 -로 구간을 나타내는 패턴
            r'(?:(\d{1,2})(?::(\d{2}))?\s*|' + // 시:분 (선택적)
            r'(\d{1,2})시(?:\s*(\d{2})분)?)?\s+', // HH시 MM분 형식
        multiLine: true,
      );

      DateTime now = DateTime.now();
      for (String line in lines) {
        if (line.trim().isNotEmpty) {
          // 일정 정보 추출
          Match? match = datePattern.firstMatch(line.trim());
          if (match != null) {
            // 날짜, 시간, 이벤트 내용 추출
            String? yearStr = match.group(1) ?? '';
            String? monthStr = match.group(2) ?? now.month.toString();
            String? dayStr = match.group(3) ?? now.day.toString();
            String? hourStr = match.group(6) ?? match.group(8) ?? '00';
            String? minuteStr = match.group(7) ?? match.group(9) ?? '00';

            String eventDate = '$yearStr $monthStr $dayStr $hourStr:$minuteStr';

            detectedDateLines.add(eventDate.trim());
          }
        }
      }

      // 일정 정보를 감지한 후 상태를 업데이트
      setState(() {
        _detectedDateLines = detectedDateLines;
      });

      // 요약 추천 로직 (100자 이상 입력 시)
      if ((text.length >= 100 || urls.isNotEmpty) &&
          !_shouldShowSummaryRecommendation) {
        setState(() {
          _shouldShowSummaryRecommendation = true;
        });
      } else if (text.length < 100 && _shouldShowSummaryRecommendation) {
        setState(() {
          _shouldShowSummaryRecommendation = false;
        });
      }

      // 분류 버튼 표시 로직 (150자 이상 입력 시)
      if (text.length >= 150 && !_shouldShowClassificationButton) {
        setState(() {
          _shouldShowClassificationButton = true;
        });
      } else if (text.length < 150 && _shouldShowClassificationButton) {
        setState(() {
          _shouldShowClassificationButton = false;
        });
      }

      if (text.isNotEmpty) {
        // 새로 입력된 텍스트에 대한 언어 감지
        final detectedLanguages = await _detectLanguages(text);

        // 감지된 언어를 기존에 감지된 언어와 합치기
        _currentDetectedLanguages.addAll(detectedLanguages);

        print('현재 감지된 언어들: $_currentDetectedLanguages'); // 감지된 전체 언어 확인

        // 여러 언어가 섞여 있으면 번역 버튼 표시
        if (_currentDetectedLanguages.contains('und')) {
          setState(() {
            _shouldShowTranslationRecommendation = false; // 'und'일 경우 번역 비활성화
          });
        } else if (_currentDetectedLanguages.contains('ko') &&
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

      // 화상회의 텍스트가 감지되면 회의 버튼 표시
      if (detectedMeetingTexts.isNotEmpty) {
        setState(() {
          _shouldShowVideoCallButton = true; // 회의 버튼 표시 플래그
        });
      } else {
        setState(() {
          _shouldShowVideoCallButton = false; // 회의 버튼 숨기기
        });
      }
    });
  }

  Future<void> _searchPlaceWithKakaoAPI(String placeName) async {
    final url = 'https://dapi.kakao.com/v2/local/search/keyword.json?query=${Uri.encodeComponent(placeName)}';
    print(placeName);
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'KakaoAK $kakaoApiKey',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['documents'] != null && data['documents'].length > 0) {
        final item = data['documents'][0];
        final mapUrl = 'https://map.kakao.com/link/map/${item['place_name']},${item['y']},${item['x']}';

        _showPlaceButton(placeName, mapUrl);
      } else {
        print('장소를 찾을 수 없습니다.');
      }
    } else {
      print('카카오 API 호출 실패: ${response.statusCode}');
    }
  }

  void _showPlaceButton(String placeName, String placeInfo) {
    setState(() {
      _detectedPlaces.add(placeName);
      _placeInfoMap[placeName] = placeInfo; // 장소와 정보를 매핑
    });
  }

  Future<void> _openMap(String url) async {
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => Scaffold(
    //       appBar: AppBar(
    //         title: Text('지도 보기'),
    //       ),
    //       body: InAppWebView(
    //         initialUrlRequest: URLRequest(url: WebUri(url)),
    //       ),
    //     ),
    //   ),
    // );
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

    // 텍스트를 단어 단위로 분리
    List<String> words = text.split(RegExp(r'\s+'));

    Set<String> detectedLanguages = {};

    try {
      // 각 단어에 대해 언어 감지 수행
      for (String word in words) {
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'q': word}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final detections = data['data']['detections'];

          if (detections != null && detections.isNotEmpty) {
            for (var detection in detections) {
              for (var langData in detection) {
                detectedLanguages.add(langData['language']);
              }
            }
          }
        }
      }

      if(detectedLanguages.contains('und')) {
        detectedLanguages.remove('und');
      }
      print('감지된 언어: $detectedLanguages');
      return detectedLanguages;
    } catch (e) {
      print('오류 발생: $e');
      return {};
    }
  }

  Future<void> _classifyMemo() async {
    final apiUrl = 'https://api.openai.com/v1/chat/completions';
    final memoContent = _controller.text;

    if (memoContent.trim().isEmpty) {
      _showMessage('메모 내용이 비어 있습니다.');
      return;
    }

    // 분류를 위한 프롬프트 설정
    final messages = [
      {
        'role': 'system',
        'content': '''
분석 결과를 다음과 같은 포맷으로 나누어 반환해 주세요:
[
    {
        "index": 1,
        "title": "제목",
        "content": "메모 원본 내용"
    },
    ...
]
모든 내용은 중략 없이 원본 텍스트를 무슨 일이 있어도 무조건 전부 반환해 주세요. 절대로 전체 내용을 반환해야 된다는 걸 명심하세요.
'''
      },
      {'role': 'user', 'content': memoContent},
    ];

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openapiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4',
          'messages': messages,
          'max_tokens': 4096, // 더 큰 토큰 수로 설정
          'temperature': 0.0,
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        print(responseBody);
        final classification = data['choices'][0]['message']['content'].trim();

        // 응답이 중간에 잘렸는지 확인
        if (data['choices'][0]['finish_reason'] == 'length') {
          print('응답이 잘렸습니다. 추가 요청을 해야 할 수 있습니다.');
          _showMessage('응답이 너무 길어 잘렸습니다.');
          return;
        }

        final List<dynamic> classificationJson = jsonDecode(classification);

        setState(() {
          _classification = classificationJson.map((item) {
            return {
              'title': item['title'],
              'content': item['content'],
            };
          }).toList();
        });
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        print('Failed to classify memo: ${response.statusCode}');
        print('Error body: $errorBody');
        _showMessage('메모 분류 중 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('Error during classification: $e');
      _showMessage('메모 분류 중 오류가 발생했습니다.');
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

    // 감지된 URL에서 내용을 가져와서 함께 요약할 준비
    String combinedContent = _controller.text;

    for (String filePath in _filePaths) {
      if (filePath.endsWith('.docx')) {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final text = docxToText(bytes);
        if (text != null) {
          combinedContent += '\n\n' + text;
        }
      } else if (filePath.endsWith('.pdf')) {
        // PDF 파일 처리 로직 추가 가능
      } else if (filePath.endsWith('.ppt') || filePath.endsWith('.pptx')) {
        // PowerPoint 파일 처리 로직 추가 가능
      }
    }

    for (String detectedUrl in _detectedUrls) {
      final urlContent = await _fetchUrlContent(detectedUrl);
      if (urlContent != null) {
        combinedContent += '\n\n' + urlContent;
      }
    }

    // 메시지 배열을 설정하여 "- ~" 형태의 목록 요약 요청
    final messages = [
      {
        'role': 'system',
        'content':
        'Summarize the following content in exactly 3 bullet points in Korean. Each bullet point should start with "- " and be concise.'
      },
      {'role': 'user', 'content': combinedContent}
    ];

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openapiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 500, // 요약 길이 조정
          'temperature': 0.5, // 더 일관된 답변 생성
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        print(data);
        final summary = data['choices'][0]['message']['content'].trim();
        print(summary);
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
      final arguments = '-i $m4aFilePath -ac 1 $wavFilePath';

      await FFmpegKit.execute(arguments);

      print('Conversion successful');
      return wavFilePath; // 변환된 wav 파일의 경로를 반환합니다.
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

    if (_classification.isNotEmpty) {
      await _showSaveDialog();
    } else {
      await _saveIndividualMemo(
          _controller.text, _backgroundColor, _mediaPaths, _filePaths);
    }
  }

  Future<void> _showSaveDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('메모 저장 방식 선택'),
          content: Text('메모를 분류해서 저장하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                // 분류된 메모 별로 각각 저장
                for (var classifiedMemo in _classification) {
                  await _saveClassifiedMemo(classifiedMemo);
                }
                Navigator.of(context)
                    .popUntil((route) => route.isFirst); // 홈으로 돌아가기
              },
              child: Text('분류 저장'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                await _saveIndividualMemo(_controller.text, _backgroundColor,
                    _mediaPaths, _filePaths); // 전체 저장
                Navigator.of(context)
                    .popUntil((route) => route.isFirst); // 홈으로 돌아가기
              },
              child: Text('전체 저장'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveClassifiedMemo(Map<String, dynamic> classifiedMemo) async {
    String memoContent = classifiedMemo['content'];
    String generatedTitle =
    await generateTitle(classifiedMemo['title'] ?? '제목 없음');

    String memoId = _generateRandomId();

    var url = Uri.parse('$SERVER_IP/memo');
    var request = http.MultipartRequest('POST', url);

    // 필수 필드 추가
    request.fields['userId'] = USER_ID;
    request.fields['posX'] = '100'; // 위치, 크기 예시
    request.fields['posY'] = '100';
    request.fields['width'] = '400';
    request.fields['height'] = '300';
    request.fields['memo_id'] = memoId;
    request.fields['title'] = generatedTitle;
    request.fields['is_read'] = 1.toString();
    request.fields['sender_user_id'] = USER_ID;
    request.fields['data_txt'] = memoContent.isNotEmpty ? memoContent : "";

    // 미디어 파일 추가
    for (var filePath in _mediaPaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    // 기타 파일 추가
    for (var filePath in _filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    var response = await request.send();
    if (response.statusCode == 201) {
      print('분류된 메모 저장 성공: $generatedTitle');
    } else {
      print('분류된 메모 저장 실패: ${response.statusCode}');
    }
  }

  Future<void> _saveIndividualMemo(String content, Color backgroundColor,
      List<String> mediaPaths, List<String> filePaths) async {
    if (widget.initialMemoId != null) {
      await _deleteMemoFromServer(widget.initialMemoId!);
    }

    widget.initialMemoId ??= _generateRandomId();
    String generatedTitle =
    await generateTitle(content.isEmpty ? '미디어 메모' : content);

    var url = Uri.parse('$SERVER_IP/memo');
    var request = http.MultipartRequest('POST', url);

    // 필수 필드 추가
    request.fields['userId'] = USER_ID;
    request.fields['theme'] = getColorName(backgroundColor);
    request.fields['posX'] = '100';
    request.fields['posY'] = '100';
    request.fields['width'] = '400';
    request.fields['height'] = '300';
    request.fields['memo_id'] = widget.initialMemoId!;
    request.fields['title'] = generatedTitle;
    request.fields['is_read'] = 1.toString();
    request.fields['sender_user_id'] = USER_ID;
    request.fields['data_txt'] = content.isNotEmpty ? content : "";

    // 미디어 파일 추가
    for (var filePath in mediaPaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    // 기타 파일 추가
    for (var filePath in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', filePath));
    }

    var response = await request.send();
    if (response.statusCode == 201) {
      print('메모 저장 성공');
    } else {
      print('메모 저장 실패: ${response.statusCode}');
    }
  }

  Future<String?> _fetchUrlContent(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // HTML 파싱
        dom.Document document = htmlParser.parse(response.body);

        // 필요 없는 태그들 제거 (버튼, 링크 등)
        document
            .querySelectorAll('a, button, script, style')
            .forEach((element) {
          element.remove();
        });

        // 텍스트만 추출
        final textContent = document.body?.text ?? '';

        return textContent.trim();
      } else {
        print('URL content 불러오기 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('URL content fetch 실패: $e');
      return null;
    }
  }

  bool _isEventLine(String line) {
    RegExp pattern = RegExp(
      r'(?:(\d{4})년\s*)?' + // 연도 (선택적)
          r'(?:(\d{1,2})[월./-]\s*)?' + // 월 (없을 수 있음)
          r'(?:(\d{1,2})(?:[일]?)?)' + // 일 (있어야 함)
          r'(?:\s*[~-]\s*(?:(\d{1,2})[월./-]\s*)?(?:(\d{1,2})[일]?)?)?\s*' + // ~ 또는 -로 구간을 나타내는 패턴
          r'(?:(\d{1,2})(?::(\d{2}))?\s*|' + // 시:분 (선택적)
          r'(\d{1,2})시(?:\s*(\d{2})분)?)?\s+' + // HH시 MM분 형식
          r'(.+)$', // 이벤트 설명
      multiLine: true,
    );
    return pattern.hasMatch(line);
  }

  Future<bool> _isDateUsingGPT(String text) async {
    final url = 'https://api.openai.com/v1/chat/completions';

    final messages = [
      {
        'role': 'system',
        'content': '아래 텍스트가 날짜나 시간인지 확인하고, 맞으면 "Yes"라고 답변하고, 아니면 "No"라고 답변해주세요.'
      },
      {'role': 'user', 'content': text}
    ];

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openapiKey', // 여기에 OpenAI API 키를 입력하세요.
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 5,
          'temperature': 0.0,
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        final answer = data['choices'][0]['message']['content'].trim();
        print('answer: $answer');
        if(answer == 'no') return false;
        return answer.toLowerCase() == 'yes';
      } else {
        print('GPT API 호출 실패: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('날짜 판별 중 오류 발생: $e');
      return false;
    }
  }

  Future<void> _showMultiEventConfirmationDialog(
      List<String> eventLines) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('추가된 일정'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: eventLines.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(eventLines[index]),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                Navigator.of(context)
                    .popUntil((route) => route.isFirst); // 홈으로 돌아가기
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                for (String line in eventLines) {
                  await _processEventLine(line); // 각 일정을 처리
                }
                Navigator.of(context)
                    .popUntil((route) => route.isFirst); // 홈으로 돌아가기
              },
              child: Text('추가'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processEventLine(String line) async {
    // 메소드 시작 시점에서만 현재 날짜 및 시간을 가져옴
    DateTime now = DateTime.now(); // 현재 시간을 가져옴
    print("현재 날짜: ${now.year}-${now.month}-${now.day}"); // 디버깅용 출력

    // 개선된 정규식 패턴 (연속 구간 처리 추가)
    RegExp pattern = RegExp(
      r'(?:(\d{4})년\s*)?' + // 연도 (선택적)
          r'(?:(\d{1,2})[월./-]\s*)?' + // 월 (없을 수 있음)
          r'(?:(\d{1,2})(?:[일]?)?)' + // 일 (없을 수 있음, 없을 경우 오늘 날짜로)
          r'(?:\s*[~-]\s*(?:(\d{1,2})[월./-]\s*)?(?:(\d{1,2})[일]?)?)?\s*' + // ~ 또는 -로 구간을 나타내는 패턴
          r'(?:(\d{1,2})(?::(\d{2}))?\s*|' + // 시:분 (선택적)
          r'(\d{1,2})시(?:\s*(\d{2})분)?)?\s+' + // HH시 MM분 형식
          r'(.+)$', // 이벤트 설명
      multiLine: true,
    );

    Iterable<Match> matches = pattern.allMatches(line);
    if (matches.isNotEmpty) {
      for (Match match in matches) {
        // 매칭된 정보를 기반으로 연, 월, 일 계산
        String? yearStr = match.group(1);
        int year =
        yearStr != null ? int.parse(yearStr) : now.year; // 연도가 없으면 올해

        String? monthStr = match.group(2);
        int month =
        monthStr != null ? int.parse(monthStr) : now.month; // 월이 없으면 이번 달

        String? dayStr = match.group(3);
        int day = dayStr != null ? int.parse(dayStr) : now.day; // 일이 없으면 오늘

        // 연속된 일정 구간을 위한 종료일 파싱
        String? endMonthStr = match.group(4);
        int endMonth = endMonthStr != null ? int.parse(endMonthStr) : month;

        String? endDayStr = match.group(5);
        int endDay = endDayStr != null ? int.parse(endDayStr) : day;

        // 시간 파싱
        String? hourStr = match.group(6);
        String? minuteStr = match.group(7);
        String? hourKoreanStr = match.group(8);
        String? minuteKoreanStr = match.group(9);

        int hour = 0;
        int minute = 0;

        if (hourStr != null) {
          hour = int.parse(hourStr);
          minute = minuteStr != null ? int.parse(minuteStr) : 0;
        } else if (hourKoreanStr != null) {
          hour = int.parse(hourKoreanStr);
          minute = minuteKoreanStr != null ? int.parse(minuteKoreanStr) : 0;
        }

        String eventDescription = match.group(10)!.trim();

        if (!_isValidTime(hour, minute)) {
          print('Invalid time format: $hour시 $minute분');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('유효하지 않은 시간 형식입니다: $hour시 $minute분')),
          );
          continue;
        }

        // 시작일과 종료일을 계산하여 해당 범위의 날짜를 모두 추가
        DateTime startDate = DateTime(year, month, day, hour, minute);
        DateTime endDate = DateTime(year, endMonth, endDay, hour, minute);

        if (startDate.isAfter(endDate)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('종료일이 시작일보다 빠릅니다.')),
          );
          continue;
        }

        for (DateTime currentDate = startDate;
        currentDate.isBefore(endDate) ||
            currentDate.isAtSameMomentAs(endDate);
        currentDate = currentDate.add(Duration(days: 1))) {
          String eventDateTimeString =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(currentDate);

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
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('일정 형식이 올바르지 않습니다.')),
      );
    }
  }

  // 유효한 시간인지 확인하는 함수
  bool _isValidTime(int hour, int minute) {
    return (hour >= 0 && hour < 24) && (minute >= 0 && minute < 60);
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
        controller.setVolume(0.0);

        setState(() {
          _videoControllers[index] = controller;
          _videoControllers[index]?.play(); // 필요에 따라 자동 재생
        });
      }).catchError((error) {
        print("비디오 초기화 실패: $error");
      });
    } catch (e) {
      print("비디오 초기화 중 오류 발생: $e");
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

  void _handleTextInputForVideoCall() async {
    String inputText = _controller.text.trim();
    RegExp videoCallPattern =
    RegExp(r"(.+?)(랑|와|과)\s*(화상회의|회의|얘기|이야기|대화)\s*하기?");

    Match? match = videoCallPattern.firstMatch(inputText);
    if (match != null) {
      String friendName = match.group(1)!;

      // 친구 목록을 서버에서 가져옴
      final response =
      await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Map<String, String>> friends = data
            .map<Map<String, String>>((friend) => {
          'user_name': friend['friend_name_set'],
          'user_id': friend['friend_id'],
        })
            .toList();

        String? friendId;
        List<String> selectedFriendIds = [];
        for (var friend in friends) {
          if (friend['user_name'] == friendName) {
            friendId = friend['user_id'];
            selectedFriendIds.add(friendId!);
            break;
          }
        }
        // VideoCallScreen으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              selectedFriendIds: selectedFriendIds, // 초대된 친구의 ID 리스트 전달
            ),
          ),
        );
      } else {
        _showMessage('친구 목록을 불러오는 데 실패했습니다.');
      }
    }
  }

  Future<void> _sendVideoCallInvite(String friendId) async {
    final url = Uri.parse('$SERVER_IP/send-video-call-invite');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'sourceUserId': USER_ID,
        'targetUserId': friendId,
      }),
    );

    if (response.statusCode == 200) {
      print('화상회의 초대 링크 전송 성공');
    } else {
      print('화상회의 초대 링크 전송 실패: ${response.statusCode}');
    }
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
    if (index >= 0 && index < _mediaPaths.length) {
      setState(() {
        _mediaPaths.removeAt(index);
        if (_videoControllers.length > index &&
            _videoControllers[index] != null) {
          _videoControllers[index]?.dispose();
          _videoControllers.removeAt(index);
        }
        _selectedMediaIndex = null;
      });
    } else {
      print('Invalid index: $index, _mediaPaths length: ${_mediaPaths.length}');
    }
  }

  void _removeFile(int index) {
    setState(() {
      _filePaths.removeAt(index);
    });
  }

  List<String> _extractUrls(String text) {
    RegExp urlRegExp = RegExp(
      r'(https?:\/\/[^\s]+)',
      caseSensitive: false,
      multiLine: true,
    );

    Iterable<RegExpMatch> matches = urlRegExp.allMatches(text);
    List<String> urls = matches.map((match) => match.group(0)!).toList();
    return urls;
  }

  // 제목 생성 함수
  Future<String> generateTitle(String text) async {
    if (text.trim().isEmpty) {
      if (_filePaths.isNotEmpty) {
        if (_filePaths.length == 1) {
          // 파일이 1개일 경우 파일 이름을 제목으로 설정
          final fileName = _filePaths[0].split('/').last;
          return "파일: $fileName";
        } else {
          // 파일이 여러 개일 경우 파일 개수를 제목으로 설정
          return "파일 ${_filePaths.length}개가 포함된 메모";
        }
      } else {
        return "제목 없음"; // 기본 제목 설정
      }
    }

    // URL 추출
    List<String> urls = _extractUrls(text);
    String combinedContent = text;

    // 각 URL의 내용을 가져와 결합 (URL은 제거하고, 그 내부 내용을 combinedContent에 포함)
    for (String url in urls) {
      String? urlContent = await _fetchUrlContent(url);
      if (urlContent != null && urlContent.isNotEmpty) {
        combinedContent = combinedContent.replaceAll(url, ''); // URL 제거
        combinedContent += '\n\nURL 내용:\n' + urlContent; // URL 내용 추가
      }
    }

    // 텍스트가 15자 이하인 경우, URL 내용을 포함한 전체 텍스트로 제목 생성
    if (combinedContent.length <= 18) {
      return combinedContent;
    }

    final urlApi = 'https://api.openai.com/v1/chat/completions';

    // 메시지 배열을 설정하여 제목 요청
    final messages = [
      {
        'role': 'system',
        'content':
        '아래의 내용과 포함된 URL의 내용을 참고하여, 최대 18자 이내의 간결한 제목을 생성해 주세요. 쌍따옴표, 따옴표는 넣지 말아주세요. 제목은 한국어로 작성해 주세요.'
      },
      {'role': 'user', 'content': combinedContent}
    ];

    try {
      final response = await http.post(
        Uri.parse(urlApi),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openapiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 20, // 제목은 짧으므로 토큰 제한을 낮게 설정
          'temperature': 0.0, // 생성 다양성 조정
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        String generatedTitle = data['choices'][0]['message']['content'].trim();
        print('메모 제목: $generatedTitle');
        return generatedTitle;
      } else {
        throw Exception('Failed to generate title');
      }
    } catch (e) {
      print('Error occurred: $e');
      return "제목 생성 실패"; // 실패 시 기본 제목 반환
    }
  }

  List<String> extractKeyPhrases(String text) {
    // 예시: 간단한 키워드 추출 (실제 로직은 더욱 복잡할 수 있습니다)
    List<String> words = text.split(RegExp(r'\s+'));
    List<String> keyPhrases = words.where((word) => word.length > 1).toList();

    return keyPhrases;
  }

  Future<double> _calculateOffset(int index) async {
    // 텍스트 스타일 가져오기
    TextStyle textStyle = TextStyle(
      fontSize: 16.0,
      color: Colors.black,
    );

    // 메모 텍스트에서 해당 위치까지의 텍스트 추출
    String textUpToIndex = _controller.text.substring(0, index);

    // TextPainter 설정
    TextPainter textPainter = TextPainter(
      text: TextSpan(text: textUpToIndex, style: textStyle),
      textDirection: ui.TextDirection.ltr,
    );

    // 레이아웃 계산
    textPainter.layout(
      maxWidth: _focusNode.context?.size?.width ?? 0,
    );

    // y 오프셋 반환
    return textPainter.height;
  }

  // 파일 아이템 UI
  Widget _buildFileTile(String filePath, int index, int realIndex) {
    final fileName = filePath.split('/').last;
    final isPdf = filePath.endsWith('.pdf');
    final isExcel = filePath.endsWith('.xls') || filePath.endsWith('.xlsx');
    final isPpt = filePath.endsWith('.ppt') || filePath.endsWith('.pptx');
    final isDocx = filePath.endsWith('.docx');
    final isHwp = filePath.endsWith('.hwp'); // 한글 파일 확장자
    final isZip = filePath.endsWith('.zip'); // 추가된 부분

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
    } else if (isZip) {
      iconData = Icons.folder_zip; // Zip 파일 아이콘
      iconColor = Colors.black;
    } else {
      iconData = Icons.insert_drive_file; // 기본 파일 아이콘
      iconColor = Colors.grey;
    }

    if (isDocx || isPdf || isPpt) {
      _shouldShowSummaryRecommendation = true;
    }

    return GestureDetector(
      onTap: () {
        OpenFile.open(filePath);
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.0),
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
            SizedBox(width: 10.0),
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
            padding:
            const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
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

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        resizeToAvoidBottomInset: true, // 키보드에 의해 위젯이 가려지지 않도록 설정
        backgroundColor: Color(0xFFFAFAFA),
        appBar: AppBar(
          backgroundColor: Color(0xFFFAFAFA),
          leading: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: BackButton(
              color: Colors.black,
              onPressed: () async {
                await _saveMemoToServer();
                Navigator.of(context).popUntil((route) => route.isFirst);
                // if (eventLines.isNotEmpty) {
                //   _showMultiEventConfirmationDialog(eventLines);
                // } else {
                //
                // }
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
                  if (_shouldShowVideoCallButton)
                    IconButton(
                      icon: Image.asset(
                        'assets/images/conference.png',
                        height: 40,
                      ),
                      onPressed: _handleTextInputForVideoCall, // 회의 시작 함수 호출
                    ),
                  if (_shouldShowClassificationButton)
                    IconButton(
                      onPressed: _classifyMemo,
                      icon: Image.asset(
                        'assets/images/classify.png',
                        height: 40,
                      ),
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
                SizedBox(
                  height: 30.0,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: SizedBox(
                        height: 100,
                        width: 100,
                        child:
                        Image.asset('assets/images/insert_file.png'),
                      ),
                      onPressed: _pickImageOrFile,
                    ),
                    IconButton(
                      icon: SizedBox(
                        height: 100,
                        width: 100,
                        child: _isRecording
                            ? Icon(Icons.stop,
                            color: Colors.red, size: 30)
                            : Image.asset(
                            'assets/images/record_duck.png'),
                      ),
                      onPressed:
                      _isRecording ? _stopRecording : _startRecording,
                    ),
                    IconButton(
                      icon: SizedBox(
                        height: 100,
                        width: 100,
                        child: Image.asset('assets/images/send_duck.png'),
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
                    color: Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context)
                          .requestFocus(_focusNode); // 텍스트 필드에 포커스를 줌
                    },
                    child: Column(
                      children: [
                        if (_mediaPaths.isNotEmpty)
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
                            padding:
                            EdgeInsets.symmetric(horizontal: 16.0),
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
                              controller: _textScrollController, // 추가된 부분
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
                ),
                if (_detectedUrls.isNotEmpty)
                  Container(
                    width: screenWidth * 0.9,
                    padding: EdgeInsets.symmetric(vertical: 10.0),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _detectedUrls.map((url) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            _launchURL(url);
                          },
                          child: Text(
                            url.length > 30
                                ? '${url.substring(0, 30)}...'
                                : url,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                if (_detectedPlaces.isNotEmpty)
                  Column(
                    children: _detectedPlaces.map((place) {
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          String? url = _placeInfoMap[place];
                          if (url != null) {
                            _openMap(url);
                          }
                        },
                        child: Text('지도 : $place'),
                      );
                    }).toList(),
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
                if (_detectedDateLines.isNotEmpty)
                  Column(
                    children: _detectedDateLines.map((line) {
                      return ElevatedButton(
                        onPressed: () {
                          _processEventLine(line);
                          _detectedDateLines.remove(line);
                        },
                        child: Text('$line'),
                      );
                    }).toList(),
                  ),
                if (_classification.isNotEmpty) SizedBox(height: 20.0),
                if (_classification.isNotEmpty)
                  Column(
                    children: _classification.map((item) {
                      return GestureDetector(
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(
                              text:
                              '${item['title']}: ${item['content']}'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                Text('Classification 텍스트가 복사되었습니다!')),
                          );
                        },
                        child: Container(
                          width: screenWidth * 0.9,
                          padding: EdgeInsets.all(16.0),
                          margin: EdgeInsets.symmetric(vertical: 8.0),
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
                                item['title'],
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              SizedBox(height: 8.0),
                              Text(
                                item['content'],
                                style: TextStyle(
                                  fontSize: 14.0,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                SizedBox(height: 10.0),
                Align(
                  alignment: Alignment.bottomCenter,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
