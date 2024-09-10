import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';
import 'dart:typed_data'; // Uint8List를 사용하기 위해 추가
import 'dart:io'; // File 클래스를 사용하기 위해 추가
import '../../socket_service.dart';
import '../calendar/calendar_screen.dart';
import '../friends_list/friends_list_screen.dart';
import '../video_call/video_call_screen.dart';
import '../write_memo/write_memo_screen.dart';
import '../login/login_screen.dart';
import 'package:sticker_memo/globals.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> memos = [];
  List<Map<String, dynamic>> datas = [];
  List<Map<String, dynamic>> filteredMemos = [];
  List<String> memoTexts = [];
  List<VideoPlayerController?> _homeVideoControllers = [];
  bool isSelectionMode = false;
  Set<int> selectedMemos = Set<int>();
  Uint8List? imageData;
  int count = 0;
  final TextEditingController _searchController = TextEditingController();
  final SocketService _socketService = SocketService();

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

  @override
  void initState() {
    super.initState();
    _fetchMemos();
    _searchController.addListener(_filterMemos);
  }

  Future<void> _fetchMemos() async {
    count = 0;
    setState(() {
      datas.clear();
    });

    final url = Uri.parse('$SERVER_IP/memo/$USER_ID');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> memo = json.decode(response.body);
        List<Future<void>> fetchDetailFutures = [];
        setState(() {
          memos = memo.map((item) {
            String memoId = item['memo_id'];
            fetchDetailFutures.add(_fetchMemoDetails(memoId)); // 비동기 작업 리스트에 추가
            return {
              'color': colorMap[item['theme']] ?? Colors.white,
              'isPinned': false,
              'memo_id': memoId,
              'timestamp': DateTime.parse(item['date']), // 작성 시간 추가
              'title': item['title']
            };
          }).toList();
        });

        print(memos);
        await Future.wait(fetchDetailFutures); // 모든 비동기 작업이 완료될 때까지 기다림
      } else {
        print('Failed to load memos: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memos: $e');
    }
    print(memoTexts);
    _filterMemos();
  }

  Future<void> _fetchMemoDetails(String memoId) async {
    final url = Uri.parse('$SERVER_IP/memo/$memoId/data');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> memoData = json.decode(response.body);
        int originalIndex = -1;

        for (var item in memos) {
          if (item['memo_id'] == memoId) {
            originalIndex = memos.indexOf(item);
            break;
          }
        }

        if (originalIndex != -1) {
          datas.removeWhere(
              (data) => data['originalIndex'] == originalIndex.toString());

          List<Map<String, dynamic>> memoItems = [];

          for (var item in memoData) {
            memoItems.add({
              'memo_id': item['memo_id'],
              'data_id': item['data_id'],
              'format': item['format'],
              'content_type': item['content_type'],
            });
          }

          datas.add({
            'originalIndex': originalIndex.toString(),
            'data': memoItems,
          });
        }
      } else {
        print('Failed to load memo datas: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memo datas: $e');
    }
  }

  Future<Widget> _getDataWidget(
      String title, String dataId, String format, int index) async {
    if (format == 'txt' && title != "미디어 메모") {
      // 메모에 텍스트가 있을 경우
      return FutureBuilder<String?>(
        future: _getData(dataId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              return Text(
                title, // 제목을 표시
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
              );
            } else {
              return Text('데이터를 불러올 수 없습니다.');
            }
          } else {
            return CircularProgressIndicator();
          }
        },
      );
    } else if (format == 'mp4' || format == 'MOV') {
      // 비디오 컨트롤러가 이미 존재하는지 확인
      if (_homeVideoControllers.length > index &&
          _homeVideoControllers[index] != null) {
        return AspectRatio(
          aspectRatio: _homeVideoControllers[index]!.value.aspectRatio,
          child: VideoPlayer(_homeVideoControllers[index]!),
        );
      } else {
        // 비디오를 다운로드하고 컨트롤러를 초기화
        final videoPath = await _getVideo(dataId);
        if (videoPath != null) {
          _initializeVideoController(videoPath, index);
          return AspectRatio(
            aspectRatio: _homeVideoControllers[index]!.value.aspectRatio,
            child: VideoPlayer(_homeVideoControllers[index]!),
          );
        } else {
          return Text('비디오를 불러올 수 없습니다.');
        }
      }
    } else if (format == 'jpg' || format == 'png' || format == 'jpeg') {
      return FutureBuilder<Uint8List?>(
        future: _getImage(dataId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              return AspectRatio(
                aspectRatio: 1,
                child: Image.memory(snapshot.data!, fit: BoxFit.cover),
              );
            } else {
              return Text('이미지를 불러올 수 없습니다.');
            }
          } else {
            return CircularProgressIndicator();
          }
        },
      );
    } else {
      return Text('지원하지 않는 형식입니다.');
    }
  }

  void _initializeVideoController(String videoPath, int index) {
    try {
      final controller = VideoPlayerController.file(File(videoPath));

      controller.initialize().then((_) {
        setState(() {
          if (_homeVideoControllers.length <= index) {
            _homeVideoControllers.length = index + 1;
          }
          _homeVideoControllers[index] = controller;
          _homeVideoControllers[index]?.play(); // Auto-play the video
        });
      }).catchError((error) {
        print("Video initialization failed: $error");
      });
    } catch (e) {
      print("Error initializing video: $e");
    }
  }

  Future<String?> _getData(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        String text = utf8.decode(response.bodyBytes);
        if (!memoTexts.contains(text)) memoTexts.add(text);
        return text;
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
        imageData = response.bodyBytes;
        return imageData;
      } else {
        print('Failed to load image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('이미지 불러오기 실패: $e');
      return null;
    }
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

  void _filterMemos() {
    String query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        filteredMemos = memos;
      } else {
        filteredMemos = memos.where((memo) {
          // 미디어가 포함된 메모는 검색 결과에서 제외
          bool hasMedia = memo['hasMedia'] ?? false;
          if (hasMedia) {
            return false; // 미디어가 포함된 메모는 결과에서 제외
          }

          String memoTitle = memo['title'].toLowerCase();
          int originalIndex = memos.indexOf(memo);

          String? memoText =
              memoTexts.isNotEmpty && memoTexts.length > originalIndex
                  ? memoTexts[originalIndex].toLowerCase()
                  : "";

          return memoTitle.contains(query) || memoText.contains(query);
        }).toList();
      }
    });
  }

  void _showMenu(BuildContext context, int index) {
    String memoId = memos[index]['memo_id']; // memoId 가져오기

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.push_pin),
                title: Text(memos[index]['isPinned'] ? '상단 고정 해제' : '상단 고정'),
                onTap: () {
                  Navigator.pop(context);
                  _togglePin(index);
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('공유'),
                onTap: () {
                  Navigator.pop(context);
                  _showFriendSelectionDialog(memoId); // memoId 전달
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('삭제'),
                onTap: () {
                  setState(() {
                    memoTexts.removeAt(index);
                    _deleteMemoFromServer(memoId);
                    memos.removeAt(index);
                    _fetchMemos();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMemoFromServer(String memoId) async {
    if (memoId == null) return;

    final url = Uri.parse('$SERVER_IP/memo/$memoId');
    final response = await http.delete(url);

    if (response.statusCode == 200) {
      print('메모 삭제 성공');
      setState(() {
        memos.removeWhere((memo) => memo['memo_id'] == memoId);
      });
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
    }
  }

  Future<void> _showFriendSelectionDialog(String memoId) async {
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
      bool allSelected = false; // 전체 선택 상태를 나타내는 변수

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('친구 선택'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (allSelected) {
                            selectedFriendIds.clear();
                          } else {
                            selectedFriendIds = friends
                                .map((friend) => friend['user_id']!)
                                .toList();
                          }
                          allSelected = !allSelected;
                        });
                      },
                      child: Text(allSelected ? '선택 해제' : '전체 선택'),
                    ),
                  ],
                ),
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
                          selectedFriendIds, memoId); // memoId 전달
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

  // 메모 여러 개를 공유하기 위해 새로운 메소드 생성
  Future<void> _showFriendSelectionDialogForSelectedMemos() async {
    if (selectedMemos.isEmpty) {
      _showMessage('공유할 메모를 선택해주세요.');
      return;
    }

    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, String>> friends = data
          .map<Map<String, String>>((friend) => {
                'user_name': friend['friend_name_set'],
                'user_id': friend['friend_id'],
              })
          .toList();

      List<String> selectedFriendIds = [];
      bool allSelected = false;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('친구 선택'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (allSelected) {
                            selectedFriendIds.clear();
                          } else {
                            selectedFriendIds = friends
                                .map((friend) => friend['user_id']!)
                                .toList();
                          }
                          allSelected = !allSelected;
                        });
                      },
                      child: Text(allSelected ? '선택 해제' : '전체 선택'),
                    ),
                  ],
                ),
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
                      _shareSelectedMemosWithFriends(
                          selectedFriendIds); // 선택된 메모들을 공유
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

  Future<void> _shareSelectedMemosWithFriends(
      List<String> friendUserIds) async {
    if (friendUserIds.isEmpty) {
      _showMessage('친구를 선택해주세요.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      for (String friendUserId in friendUserIds) {
        for (int index in selectedMemos) {
          String memoId = memos[index]['memo_id'];

          final url = Uri.parse('$SERVER_IP/send-memo');
          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'sourceUserId': USER_ID,
              'targetUserId': friendUserId,
              'memoId': memoId,
            }),
          );

          if (response.statusCode != 200) {
            Navigator.of(context).pop();
            _showMessage('메모 공유 실패: ${response.statusCode}');
            return;
          }
        }
      }

      Navigator.of(context).pop();
      _showMessage('메모가 성공적으로 공유되었습니다.');
    } catch (e) {
      Navigator.of(context).pop();
      _showMessage('메모 공유 중 오류 발생: $e');
    }
  }

  Future<void> _shareMemoWithFriends(
      List<String> friendUserIds, String memoId) async {
    if (friendUserIds.isEmpty) {
      _showMessage('친구를 선택해주세요.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      for (String friendUserId in friendUserIds) {
        final url = Uri.parse('$SERVER_IP/send-memo');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'sourceUserId': USER_ID,
            'targetUserId': friendUserId,
            'memoId': memoId, // 전달받은 memoId 사용
          }),
        );

        if (response.statusCode != 200) {
          Navigator.of(context).pop();
          _showMessage('메모 공유 실패: ${response.statusCode}');
          return;
        }
      }

      Navigator.of(context).pop();
      _showMessage('메모가 성공적으로 공유되었습니다.');
    } catch (e) {
      Navigator.of(context).pop();
      _showMessage('메모 공유 중 오류 발생: $e');
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

  void _togglePin(int index) {
    setState(() {
      bool isPinned = memos[index]['isPinned'];
      memos[index]['isPinned'] = !isPinned;

      if (!isPinned) {
        // 고정된 메모를 맨 위로 이동
        var memo = memos.removeAt(index);
        var data = datas.removeAt(index); // 데이터도 함께 이동
        memos.insert(0, memo);
        datas.insert(0, data); // 데이터도 함께 상단으로 이동
      } else {
        // 고정 해제 시 원래 위치로 되돌림
        var memo = memos.removeAt(index);
        var data = datas.removeAt(index); // 데이터도 함께 이동
        int originalIndex = memo['originalIndex'];
        memos.insert(originalIndex, memo);
        datas.insert(originalIndex, data); // 데이터도 원래 위치로 이동
      }

      // 고정된 메모들을 다시 정렬
      _sortMemos();
    });
  }

  void _sortMemos() {
    setState(() {
      memos.sort((a, b) {
        if (a['isPinned'] && !b['isPinned']) {
          return -1;
        } else {
          return 1;
        }
      });

      datas.sort((a, b) {
        int indexA = memos.indexWhere(
            (memo) => memo['memo_id'] == a['data'].first['memo_id']);
        int indexB = memos.indexWhere(
            (memo) => memo['memo_id'] == b['data'].first['memo_id']);
        return indexA.compareTo(indexB);
      });

      for (int i = 0; i < memos.length; i++) {
        memos[i]['originalIndex'] = i;
      }

      for (var data in datas) {
        int index = memos.indexWhere(
            (memo) => memo['memo_id'] == data['data'].first['memo_id']);
        data['originalIndex'] = index.toString();
      }
    });
  }

  void _navigateToCalendar(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CalendarScreen()),
    );
  }

  void _navigateToFriendsList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FriendsListScreen()),
    );
  }

  Future<void> _editMemo(BuildContext context, int index) async {
    if (memos[index]['format'] != 'txt') {
      imageData = await _getImage(memos[index]['memo_id']);
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteMemoScreen(
          initialColor: memos[index]['color'],
          initialMemoId: memos[index]['memo_id'],
          initialImageData: imageData,
        ),
      ),
    );

    if (result != null && result['text'].isNotEmpty) {
      setState(() {
        memos[index] = result;
      });
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      isSelectionMode = !isSelectionMode;
      if (!isSelectionMode) {
        selectedMemos.clear();
      }
    });
  }

  void _toggleMemoSelection(int index) {
    setState(() {
      if (selectedMemos.contains(index)) {
        selectedMemos.remove(index);
      } else {
        selectedMemos.add(index);
      }
    });
  }

  void _selectAllMemos() {
    setState(() {
      if (selectedMemos.length == memos.length) {
        selectedMemos.clear();
      } else {
        selectedMemos =
            Set<int>.from(List<int>.generate(memos.length, (index) => index));
      }
    });
  }

  void _deleteSelectedMemos() {
    setState(() {
      selectedMemos.forEach((index) {
        String memoId = memos[index]['memo_id'];
        memoTexts.removeAt(index);
        _deleteMemoFromServer(memoId);
      });

      _fetchMemos();
      selectedMemos.clear();
      isSelectionMode = false;
    });
  }

  Future<void> _showFriendSelectionDialogForVideoCall() async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, String>> friends = data
          .map<Map<String, String>>((friend) => {
                'user_name': friend['friend_name_set'],
                'user_id': friend['friend_id'],
              })
          .toList();

      List<String> selectedFriendNames = []; // 선택된 친구 이름을 저장하는 리스트
      bool allSelected = false; // 전체 선택 상태를 나타내는 변수

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('친구 선택'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (allSelected) {
                            selectedFriendNames.clear();
                          } else {
                            selectedFriendNames = friends
                                .map((friend) => friend['user_name']!)
                                .toList();
                          }
                          allSelected = !allSelected;
                        });
                      },
                      child: Text(allSelected ? '선택 해제' : '전체 선택'),
                    ),
                  ],
                ),
                content: Container(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      return CheckboxListTile(
                        title: Text(friends[index]['user_name']!),
                        value: selectedFriendNames
                            .contains(friends[index]['user_name']),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              selectedFriendNames
                                  .add(friends[index]['user_name']!);
                            } else {
                              selectedFriendNames
                                  .remove(friends[index]['user_name']);
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
                      // VideoCallScreen으로 선택된 친구들과 함께 이동
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoCallScreen(
                              selectedFriendNames: selectedFriendNames),
                        ),
                      );
                    },
                    child: Text('초대'),
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

  Future<Map<String, dynamic>?> _getFirstMedia(
      List<Map<String, dynamic>> memoDatas) async {
    Map<String, dynamic>? firstMedia;

    if (memoDatas.isNotEmpty) {
      // 첫 번째로 텍스트 포맷을 찾음
      firstMedia = memoDatas.firstWhere(
        (data) => data['format'] == 'txt',
        orElse: () => {},
      );

      // 텍스트 포맷이 있으면 내용을 비동기적으로 가져와서 확인
      if (firstMedia.isNotEmpty) {
        final textData = await _getData(firstMedia['data_id']);
        if (textData == null || textData.isEmpty) {
          // 텍스트가 비어있으면 이미지나 비디오를 다시 찾음
          firstMedia = memoDatas.firstWhere(
            (data) =>
                data['format'] == 'jpg' ||
                data['format'] == 'png' ||
                data['format'] == 'jpeg' ||
                data['format'] == 'mp4' ||
                data['format'] == 'MOV',
            orElse: () => {},
          );
        }
      } else {
        // 텍스트가 없을 경우 바로 이미지나 비디오 포맷을 찾음
        firstMedia = memoDatas.firstWhere(
          (data) =>
              data['format'] == 'jpg' ||
              data['format'] == 'png' ||
              data['format'] == 'jpeg' ||
              data['format'] == 'mp4' ||
              data['format'] == 'MOV',
          orElse: () => {},
        );
      }
    }

    return firstMedia;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus(); // 키보드 내리기
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: AppBar(
            title:
                isSelectionMode ? Text('${selectedMemos.length}개 선택됨') : null,
            backgroundColor: Colors.transparent,
            leading: isSelectionMode
                ? IconButton(
                    icon: Icon(Icons.close),
                    onPressed: _toggleSelectionMode,
                  )
                : null,
            actions: [
              if (isSelectionMode) ...[
                IconButton(
                  icon: Icon(Icons.select_all),
                  onPressed: _selectAllMemos,
                ),
                IconButton(
                  icon: Icon(Icons.share),
                  onPressed: _showFriendSelectionDialogForSelectedMemos,
                ),
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: _deleteSelectedMemos,
                ),
              ],
              if (!isSelectionMode) ...[
                IconButton(
                  icon: Icon(Icons.video_call_outlined),
                  onPressed: _showFriendSelectionDialogForVideoCall,
                ),
                IconButton(
                  icon: Icon(Icons.logout),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('token');
                    await prefs.remove('userId');
                    await prefs.remove('userName');

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => Login()),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _fetchMemos, // 새로고침 시 호출될 함수
          child: Padding(
            padding: const EdgeInsets.only(
                top: 50.0, left: 16.0, right: 16.0, bottom: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    Center(
                      child: Transform.translate(
                        offset: Offset(10, -25), // y값을 음수로 설정하여 이미지를 위로 이동
                        child: Image.asset(
                          'assets/images/img_logo.png',
                          height: 100,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: PopupMenuButton<int>(
                        icon: Icon(Icons.more_vert, size: 35.0),
                        onSelected: (int result) {
                          if (result == 0) {
                            _toggleSelectionMode();
                          } else if (result == 1) {
                            _navigateToCalendar(context);
                          } else if (result == 2) {
                            _navigateToFriendsList(context);
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<int>>[
                          const PopupMenuItem<int>(
                            value: 0,
                            child: Text('선택'),
                          ),
                          const PopupMenuItem<int>(
                            value: 1,
                            child: Text('캘린더'),
                          ),
                          const PopupMenuItem<int>(
                            value: 2,
                            child: Text('친구 목록'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    _filterMemos(); // 검색어 변경 시 필터링 함수 호출
                  },
                  decoration: InputDecoration(
                    hintText: '메모 검색',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE2F1FF), // 기본 상태 테두리 색상
                        width: 3.0, // 테두리 굵기
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE2F1FF), // 기본 상태 테두리 색상
                        width: 3.0, // 테두리 굵기
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE2F1FF), // 포커스 상태 테두리 색상
                        width: 3.0, // 테두리 굵기
                      ),
                    ),
                    suffixIcon:
                        Icon(Icons.search, color: Colors.grey), // 검색 아이콘
                  ),
                ),
                SizedBox(height: 16.0),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount:
                        filteredMemos.isEmpty && _searchController.text.isEmpty
                            ? memos.length
                            : filteredMemos.length,
                    itemBuilder: (context, index) {
                      var currentMemos = filteredMemos.isEmpty &&
                              _searchController.text.isEmpty
                          ? memos
                          : filteredMemos;
                      bool isSelected = selectedMemos.contains(index);

                      List<Map<String, dynamic>> memoDatas = datas
                          .where((data) =>
                              data['originalIndex'] == index.toString())
                          .expand((data) => data['data'])
                          .map<Map<String, dynamic>>(
                              (item) => item as Map<String, dynamic>)
                          .toList();

                      FutureBuilder<Map<String, dynamic>?>(
                        future: _getFirstMedia(memoDatas),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            if (snapshot.hasData &&
                                snapshot.data != null &&
                                snapshot.data!.isNotEmpty) {
                              final firstMedia = snapshot.data!;
                              return FutureBuilder<Widget>(
                                future: _getDataWidget(
                                  currentMemos[index]['title'],
                                  firstMedia['data_id'],
                                  firstMedia['format'],
                                  index,
                                ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.done) {
                                    if (snapshot.hasData) {
                                      return snapshot.data!;
                                    } else {
                                      return Text('데이터를 불러올 수 없습니다.');
                                    }
                                  } else {
                                    return CircularProgressIndicator();
                                  }
                                },
                              );
                            } else {
                              return Text('내용 없음',
                                  style: TextStyle(fontSize: 16.0));
                            }
                          } else {
                            return CircularProgressIndicator();
                          }
                        },
                      );
                      return GestureDetector(
                        onTap: isSelectionMode
                            ? () => _toggleMemoSelection(index)
                            : () => _editMemo(context, index),
                        onLongPress: () => _showMenu(context, index),
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.grey),
                                color: currentMemos[index]['color'] ??
                                    Colors.white,
                              ),
                              child: Center(
                                child: FutureBuilder<Map<String, dynamic>?>(
                                  future: _getFirstMedia(memoDatas),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.done) {
                                      if (snapshot.hasData &&
                                          snapshot.data != null &&
                                          snapshot.data!.isNotEmpty) {
                                        final firstMedia = snapshot.data!;
                                        return FutureBuilder<Widget>(
                                          future: _getDataWidget(
                                            currentMemos[index]['title'],
                                            firstMedia['data_id'],
                                            firstMedia['format'],
                                            index,
                                          ),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.done) {
                                              if (snapshot.hasData) {
                                                return snapshot.data!;
                                              } else {
                                                return const Text(
                                                    '데이터를 불러올 수 없습니다.');
                                              }
                                            } else {
                                              return const CircularProgressIndicator();
                                            }
                                          },
                                        );
                                      } else {
                                        return const Text('내용 없음',
                                            style: TextStyle(fontSize: 16.0));
                                      }
                                    } else {
                                      return const CircularProgressIndicator();
                                    }
                                  },
                                ),
                              ),
                            ),
                            if (currentMemos[index]['isPinned'])
                              Positioned(
                                top: 8.0,
                                right: 8.0,
                                child: Icon(
                                  Icons.push_pin,
                                  color: Colors.grey,
                                ),
                              ),
                            if (isSelectionMode)
                              Positioned(
                                top: 8.0,
                                left: 8.0,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue[400]
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    size: 16,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.blue[100],
          foregroundColor: Colors.blue[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => WriteMemoScreen()),
            );
            if (result != null &&
                result['text'] != null &&
                result['text'].isNotEmpty) {
              setState(() {
                result['isPinned'] = false; // 새로운 메모는 기본적으로 고정되지 않음
                memos.add(result as Map<String, dynamic>); // 명시적으로 타입을 캐스팅
              });
              _sortMemos();
            }

            _fetchMemos(); // 서버에서 최신 데이터 불러오기
            _sortMemos();
          },
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}
