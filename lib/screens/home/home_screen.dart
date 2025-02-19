import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';
import 'dart:typed_data'; // Uint8List를 사용하기 위해 추가
import 'dart:io'; // File 클래스를 사용하기 위해 추가
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
  Map<String, String> memoTexts = {};
  Map<String, Map<String, dynamic>> memoDetailsMap = {};
  List<VideoPlayerController?> _homeVideoControllers = [];
  bool isSelectionMode = false;
  Set<int> selectedMemos = Set<int>();
  Uint8List? imageData;
  int index = 0;
  final TextEditingController _searchController = TextEditingController();
  int isRead = 0;
  Set<String> pinnedMemoIds = Set<String>();

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
    index = 0;
    setState(() {
      datas.clear();
      memoDetailsMap.clear();
    });

    final url = Uri.parse('$SERVER_IP/memo/$USER_ID');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> memo = json.decode(response.body);
        setState(() {
          memos = memo.map((item) {
            String memoId = item['memo_id'];
            // 고정 상태를 기존에 저장된 pinnedMemoIds와 비교하여 설정
            bool isPinned = pinnedMemoIds.contains(memoId);
            return {
              'color': Color(0xFFF4EEE7),
              'isPinned': isPinned, // 고정 상태 설정
              'memo_id': memoId,
              'timestamp': DateTime.parse(item['date']),
              'title': item['title'],
              'originalIndex': index++, // 원래 인덱스를 저장
              'is_read': item['is_read'],
              'sender_user_id': item['sender_user_id'],
            };
          }).toList();
        });

        List<Future<void>> fetchDetailFutures = [];
        for (int i = 0; i < memos.length; i++) {
          String memoId = memos[i]['memo_id'];
          fetchDetailFutures.add(_fetchMemoDetails(memoId, i));
        }

        await Future.wait(fetchDetailFutures);
      } else {
        print('Failed to load memos: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memos: $e');
    }

    _filterMemos();
    print(memoTexts);
  }

  // 파일명에서 순서 정보 추출 함수 (HomeScreen에도 동일하게 추가)
  int _extractOrderFromFilename(String filename) {
    RegExp regExp = RegExp(r'_order_(\d+)\.');
    Match? match = regExp.firstMatch(filename);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  Future<void> _fetchMemoDetails(String memoId, int memoIndex) async {
    final url = Uri.parse('$SERVER_IP/memo/$memoId/data');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> memoData = json.decode(response.body);

        // 파일명을 기반으로 memoData를 순서대로 정렬
        memoData.sort((a, b) {
          String filenameA = a['file_name']; // 서버 응답에서 파일명 필드
          String filenameB = b['file_name'];
          int orderA = _extractOrderFromFilename(filenameA);
          int orderB = _extractOrderFromFilename(filenameB);
          return orderA.compareTo(orderB);
        });

        List<Map<String, dynamic>> memoItems = [];

        for (var item in memoData) {
          memoItems.add({
            'memo_id': item['memo_id'],
            'data_id': item['data_id'],
            'format': item['format'],
            'content_type': item['content_type'],
          });

          if (item['format'] == 'txt') {
            String dataId = item['data_id'];
            String? textContent = await _getData(dataId);
            memoTexts[memoId] = textContent ?? "";
          }
        }

        memoDetailsMap[memoId] = {
          'data': memoItems,
        };

        _updateMemos();
      } else {
        print('Failed to load memo datas: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memo datas: $e');
    }
  }

  void _updateMemos() {
    setState(() {
      for (var memo in memos) {
        final memoId = memo['memo_id'];
        if (memoDetailsMap.containsKey(memoId)) {
          final memoData = memoDetailsMap[memoId]!['data'];

          // originalIndex에 해당하는 데이터가 있는지 확인
          int existingIndex = datas.indexWhere(
            (data) =>
                data['originalIndex'] ==
                memos.indexWhere((m) => m['memo_id'] == memoId).toString(),
          );

          if (existingIndex != -1) {
            datas[existingIndex]['data'] = memoData;
          } else {
            datas.add({
              'originalIndex':
                  memos.indexWhere((m) => m['memo_id'] == memoId).toString(),
              'data': memoData,
            });
          }
        }
      }
    });
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
                style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold),
              );
            } else {
              return Text('데이터를 불러올 수 없습니다.');
            }
          } else {
            return Text("");
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
            return Text('');
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

  // void _filterMemos() {
  //   String query = _searchController.text.toLowerCase();

  //   setState(() {
  //     if (query.isEmpty) {
  //       filteredMemos = memos;
  //     } else {
  //       filteredMemos = memos.where((memo) {
  //         String memoId = memo['memo_id'];
  //         String? memoText = memoTexts.containsKey(memoId)
  //             ? memoTexts[memoId]!.trim().toLowerCase()
  //             : "";

  //         // memoText가 비어 있으면 검색 결과에서 제외
  //         if (memoText.isEmpty) {
  //           return false;
  //         }

  //         String memoTitle = memo['title'].toLowerCase();
  //         // 특정 메모의 텍스트만을 검색어와 비교
  //         return memoTitle.contains(query) || memoText.contains(query);
  //       }).toList();
  //     }
  //   });
  // }

  void _filterMemos() {
    String query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        filteredMemos = memos;
      } else {
        filteredMemos = memos.where((memo) {
          String memoId = memo['memo_id'];
          String? memoText = memoTexts.containsKey(memoId)
              ? memoTexts[memoId]!.trim().toLowerCase()
              : "";

          // memoText가 비어 있으면 검색 결과에서 제외
          if (memoText.isEmpty) {
            return false;
          }

          String memoTitle = memo['title'].toLowerCase();
          // 특정 메모의 텍스트만을 검색어와 비교
          return memoTitle.contains(query) || memoText.contains(query);
        }).toList();
      }
    });
  }

  void _reindexMemoTexts() {}
  // void _reindexMemoTexts() {
  //   // 기존 memoTexts의 인덱스를 1씩 증가시킴
  //   Map<int, String> updatedMemoTexts = {};
  //   memoTexts.forEach((key, value) {
  //     updatedMemoTexts[key + 1] = value;
  //   });
  //
  //   memoTexts = updatedMemoTexts;
  // }

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
                title: Text(
                  memos[index]['isPinned'] ? '상단 고정 해제' : '상단 고정',
                  style: TextStyle(
                    color: Color(0xFFE48758), // 텍스트 색상 설정
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _togglePin(index);
                },
              ),
              ListTile(
                leading: Icon(Icons.check),
                title: Text(
                  '선택',
                  style: TextStyle(color: Color(0xFFE48758)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleSelectionMode();
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text(
                  '공유',
                  style: TextStyle(color: Color(0xFFE48758)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showFriendSelectionDialog(memoId); // memoId 전달
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text(
                  '삭제',
                  style: TextStyle(color: Color(0xFFE48758)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    memoTexts.remove(index);
                    _deleteMemoFromServer(memoId);
                    memos.removeAt(index);
                    _reindexMemoTexts();
                    _fetchMemos();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMemoFromServer(String memoId) async {
    if (memoId.isEmpty) return;

    final url = Uri.parse('$SERVER_IP/memo/$memoId');
    final response = await http.delete(url);

    if (response.statusCode == 200) {
      print('메모 삭제 성공');
      setState(() {
        memos.removeWhere((memo) => memo['memo_id'] == memoId);
        memoTexts.remove(memoId);
        _reindexMemoTexts();
      });
      await _fetchMemos();
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
    }
    _fetchMemos();
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
                backgroundColor: Color(0xFFFAFAFA),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '친구 선택',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
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
                      child: Text(
                        allSelected ? '선택 해제' : '전체 선택',
                        style: TextStyle(
                          color: Color(0xFFE48758), // 텍스트 색상 설정
                        ),
                      ),
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
                    child: Text(
                      '취소',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 팝업 닫기
                      _shareMemoWithFriends(
                          selectedFriendIds, memoId); // memoId 전달
                    },
                    child: Text(
                      '전송',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
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
                backgroundColor: Color(0xFFFAFAFA),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '친구 선택',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
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
                      child: Text(
                        allSelected ? '선택 해제' : '전체 선택',
                        style: TextStyle(
                          color: Color(0xFFE48758), // 텍스트 색상 설정
                        ),
                      ),
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
                    child: Text(
                      '취소',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 팝업 닫기
                      _shareSelectedMemosWithFriends(
                          selectedFriendIds); // 선택된 메모들을 공유
                    },
                    child: Text(
                      '전송',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
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
          backgroundColor: Color(0xFFFAFAFA),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                '확인',
                style: TextStyle(color: Color(0xFFE48758)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _togglePin(int index) {
    setState(() {
      String memoId = memos[index]['memo_id'];
      bool isPinned = memos[index]['isPinned'];
      memos[index]['isPinned'] = !isPinned;

      if (memos[index]['isPinned']) {
        // 고정된 메모 목록에 추가 (originalIndex 포함)
        pinnedMemoIds.add(memoId);
        memos[index]['pinnedOriginalIndex'] =
            memos[index]['originalIndex']; // 원래 인덱스 저장

        // 고정된 메모를 맨 위로 이동
        var memo = memos.removeAt(index);
        var data = datas.removeAt(index); // 데이터도 함께 이동
        memos.insert(0, memo);
        datas.insert(0, data); // 데이터도 상단으로 이동
      } else {
        // 고정 해제 시 원래 위치로 되돌림
        pinnedMemoIds.remove(memoId);
        int originalIndex = memos[index]['pinnedOriginalIndex'] ??
            memos[index]['originalIndex']; // 저장된 originalIndex로 복원
        var memo = memos.removeAt(index);
        var data = datas.removeAt(index); // 데이터도 함께 이동
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
          isRead: memos[index]['is_read'],
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
        memoTexts.remove(index);
        _deleteMemoFromServer(memoId);
      });
      _reindexMemoTexts();
      _fetchMemos();
      selectedMemos.clear();
      isSelectionMode = false;
    });
    _fetchMemos();
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

      List<String> selectedFriendIds = []; // 선택된 친구의 user_id를 저장하는 리스트
      bool allSelected = false; // 전체 선택 상태를 나타내는 변수

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                backgroundColor: Color(0xFFFAFAFA),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('친구 선택'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (allSelected) {
                            selectedFriendIds.clear(); // 선택 해제
                          } else {
                            selectedFriendIds = friends
                                .map((friend) => friend['user_id']!)
                                .toList(); // 전체 선택
                          }
                          allSelected = !allSelected;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: selectedFriendIds.isEmpty
                            ? Color(0xFFFAFAFA) // 선택 해제 색상
                            : Color(0xFFE48758), // 눌렀을 때 텍스트 색상
                      ),
                      child: Text(
                        allSelected ? '선택 해제' : '전체 선택',
                        style: TextStyle(
                          color: Color(0xFFE48758), // 텍스트 색상 설정
                        ),
                      ),
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
                        activeColor: Color(0xFFE48758), // 바깥쪽 색상 설정
                        checkColor: Colors.white, // 안쪽 체크 색상 설정
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
                    child: Text(
                      '취소',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 팝업 닫기
                      // VideoCallScreen으로 선택된 친구들과 함께 이동
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoCallScreen(
                            selectedFriendIds: selectedFriendIds,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      '초대',
                      style: TextStyle(color: Color(0xFFE48758)),
                    ),
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
      List<Map<String, dynamic>> memoDatas, int index) async {
    if (memoDatas.isEmpty) return null;

    // 첫 번째로 텍스트 포맷을 찾음
    var firstMedia = memoDatas.firstWhere(
      (data) => data['format'] == 'txt',
      orElse: () => {}, // 빈 맵 대신 null 반환
    );

    // 텍스트 포맷이 있으면 내용을 비동기적으로 가져와서 확인
    if (firstMedia != null) {
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
          orElse: () => {}, // 빈 맵 대신 null 반환
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
        orElse: () => {}, // 빈 맵 대신 null 반환
      );
    }

    return firstMedia;
  }

  Future<String> _getFriendName(String senderUserId) async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      // sender_user_id와 일치하는 친구의 name_set 반환
      final friend = data.firstWhere(
        (friend) => friend['friend_id'] == senderUserId,
        orElse: () => null,
      );
      if (friend != null) {
        return friend['friend_name_set'];
      } else {
        return '알 수 없음'; // 일치하는 친구가 없을 때 기본값
      }
    } else {
      throw Exception('친구 목록을 불러오는 데 실패했습니다.');
    }
  }

  Future<String> _getName(String senderUserId) async {
    if (senderUserId == USER_ID) return '';

    // URL에 쿼리 파라미터로 userId 추가
    final url = Uri.parse('$SERVER_IP/get-username?userId=$senderUserId');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        // 응답이 성공적일 때
        final dynamic data = json.decode(response.body);

        if (data != null && data is Map && data.containsKey('name')) {
          return data['name'];
        } else {
          return '알 수 없음';
        }
      } else {
        // 응답 코드가 200이 아닐 때
        print('모르는 사람 이름 불러오기 실패: ${response.statusCode}');
        return '알 수 없음';
      }
    } catch (e) {
      // 예외 처리
      print('Error fetching name: $e');
      return '알 수 없음';
    }
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
            ],
          ),
        ),
        drawer: Drawer(
          backgroundColor: Color(0xFFF4EEE7),
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              UserAccountsDrawerHeader(
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Color(0xFFF4EEE7),
                  child: Icon(
                    Icons.person,
                    size: 40.0,
                    color: Color(0xFFE48758),
                  ),
                ),
                accountName: Row(
                  children: [
                    Text(
                      USER_NAME,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22.0,
                        color: Color(0xFFF4EEE7),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_outlined,
                          size: 25, color: Color(0xFFF4EEE7)), // 복사 아이콘 추가
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: USER_NAME)); // 이름 복사
                        ScaffoldMessenger.of(context).showSnackBar(
                          // 복사 완료 알림
                          SnackBar(
                              content: Text(
                            '이름이 복사되었습니다',
                            style: TextStyle(color: Color(0xFFE48758)),
                          )),
                        );
                      },
                    ),
                    SizedBox(
                      width: 68,
                    ),
                    IconButton(
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
                        icon: Icon(
                          Icons.logout,
                          size: 25,
                          color: Color(0xFFF4EEE7),
                        )),
                  ],
                ),
                accountEmail: null,
                decoration: BoxDecoration(
                  color: Color(0xFFE48758),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.calendar_month_outlined,
                  color: Color(0xFFE48758),
                ),
                title: Text(
                  '캘린더',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF939495),
                  ),
                ),
                onTap: () {
                  _navigateToCalendar(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.people,
                  color: Color(0xFFE48758),
                ),
                title: Text(
                  '친구 목록',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF939495),
                  ),
                ),
                onTap: () {
                  _navigateToFriendsList(context);
                },
              ),
              ListTile(
                  leading: Icon(
                    Icons.video_call_outlined,
                    color: Color(0xFFE48758),
                  ),
                  title: Text(
                    '화상 통신',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF939495),
                    ),
                  ),
                  onTap: () {
                    _showFriendSelectionDialogForVideoCall();
                  }),
            ],
          ),
        ),
        backgroundColor: Color(0xFFFAFAFA),
        body: RefreshIndicator(
          backgroundColor: Color(0xFFFAFAFA),
          color: Color(0xFFE48758),
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
                  ],
                ),
                TextField(
                  controller: _searchController,
                  onSubmitted: (value) {
                    _filterMemos(); // 검색어 변경 시 필터링 함수 호출
                  },
                  decoration: InputDecoration(
                    hintText: '메모 검색',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE48758), // 기본 상태 테두리 색상
                        width: 1.0, // 테두리 굵기
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE48758), // 기본 상태 테두리 색상
                        width: 1.0, // 테두리 굵기
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide(
                        color: Color(0xFFE48758), // 포커스 상태 테두리 색상
                        width: 1.0, // 테두리 굵기
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
                      int isRead = currentMemos[index]
                          ['is_read']; // Check if the memo is read
                      Color memoColor = currentMemos[index]['color'] ??
                          Colors.white; // Default color

                      String memoId = currentMemos[index]['memo_id'];
                      List<Map<String, dynamic>> memoDatas = datas
                          .where((data) =>
                              data['originalIndex'] ==
                              memos
                                  .indexWhere((m) => m['memo_id'] == memoId)
                                  .toString())
                          .expand((data) => data['data'])
                          .map<Map<String, dynamic>>(
                              (item) => item as Map<String, dynamic>)
                          .toList();

                      return GestureDetector(
                        onTap: isSelectionMode
                            ? () => _toggleMemoSelection(index)
                            : () => _editMemo(context, index),
                        onLongPress: () => _showMenu(context, index),
                        child: Stack(
                          children: [
                            AnimatedContainer(
                              duration: Duration(milliseconds: 500),
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: isRead == 1
                                      ? Color(0xFFF4EEE7)
                                      : Colors.blueAccent,
                                  width: isRead == 1 ? 1.0 : 2.0,
                                ),
                                color: currentMemos[index]['color'] ??
                                    Colors.white,
                              ),
                              child: Center(
                                child: FutureBuilder<Map<String, dynamic>?>(
                                  future: _getFirstMedia(memoDatas, index),
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
                                          builder:
                                              (context, dataWidgetSnapshot) {
                                            if (dataWidgetSnapshot
                                                    .connectionState ==
                                                ConnectionState.done) {
                                              if (dataWidgetSnapshot.hasData &&
                                                  currentMemos[index]
                                                          ['is_read'] !=
                                                      1) {
                                                return Text(
                                                  currentMemos[index]['title'],
                                                  style: TextStyle(
                                                    fontSize: 16.0,
                                                  ),
                                                );
                                              } else if (dataWidgetSnapshot
                                                  .hasData) {
                                                return dataWidgetSnapshot.data!;
                                              } else {
                                                return Text('데이터를 불러올 수 없습니다.');
                                              }
                                            } else {
                                              return Text('');
                                            }
                                          },
                                        );
                                      } else {
                                        return Text('');
                                      }
                                    } else {
                                      return Text("");
                                    }
                                  },
                                ),
                              ),
                            ),
                            // Always show sender's name in the top-left corner
                            Positioned(
                              top: 8.0,
                              left: 8.0,
                              child: FutureBuilder<String>(
                                future: _getFriendName(
                                    currentMemos[index]['sender_user_id']),
                                builder: (context, friendNameSnapshot) {
                                  if (friendNameSnapshot.connectionState ==
                                      ConnectionState.done) {
                                    if (friendNameSnapshot.hasData) {
                                      if (friendNameSnapshot.data == "알 수 없음") {
                                        return FutureBuilder<String>(
                                          future: _getName(currentMemos[index]
                                              ['sender_user_id']),
                                          builder: (context, nameSnapshot) {
                                            if (nameSnapshot.connectionState ==
                                                ConnectionState.done) {
                                              if (nameSnapshot.hasData &&
                                                  nameSnapshot.data! != '') {
                                                return Text(
                                                    'From. ${nameSnapshot.data!}',
                                                    style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 12.0,
                                                        fontWeight:
                                                            FontWeight.bold));
                                              } else {
                                                return Text('');
                                              }
                                            } else {
                                              return Text('');
                                            }
                                          },
                                        );
                                      } else {
                                        return Text(
                                            'From. ${friendNameSnapshot.data!}',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12.0,
                                                fontWeight: FontWeight.bold));
                                      }
                                    } else {
                                      return Text('');
                                    }
                                  } else {
                                    return Text('');
                                  }
                                },
                              ),
                            ),
                            if (currentMemos[index]['isPinned'])
                              Positioned(
                                top: 8.0,
                                right: 8.0,
                                child: Icon(Icons.push_pin, color: Colors.grey),
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
                                        ? Color(0xFFE48758)
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
        floatingActionButton: SizedBox(
          width: 50.0, // 원하는 너비
          height: 50.0, // 원하는 높이
          child: FloatingActionButton(
            backgroundColor: Color(0xFFE48758),
            foregroundColor: Color(0xFFFAFAFA),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30.0),
            ),
            onPressed: () async {
              // WriteMemoScreen으로 이동하고, 돌아올 때 메모 목록을 새로 고침
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => WriteMemoScreen()),
              );
              await _fetchMemos(); // 돌아온 후 메모 목록을 다시 불러옴
            },
            child: Icon(Icons.add, size: 30.0), // 아이콘 크기 조정
          ),
        ),
      ),
    );
  }
}
