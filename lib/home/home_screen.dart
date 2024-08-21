import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data'; // Uint8List를 사용하기 위해 추가
import '../calendar/calendar_screen.dart';
import '../friends_list/friends_list_screen.dart';
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
  bool isSelectionMode = false;
  Set<int> selectedMemos = Set<int>();
  Uint8List? imageData;
  int count = 0;

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
    _fetchMemos(); // user의 메모 데이터를 가져오는 함수 호출
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
        print(response.body);
        setState(() {
          memos = memo.map((item) {
            String memoId = item['memo_id'];
            fetchDetailFutures.add(_fetchMemoDetails(memoId)); // 비동기 작업 리스트에 추가
            print(DateTime.parse(item['date']));
            return {
              'color': colorMap[item['theme']] ?? Colors.white,
              'isPinned': false,
              'memo_id': memoId,
              'timestamp': DateTime.parse(item['date']), // 작성 시간 추가
            };
          }).toList();
        });

        await Future.wait(fetchDetailFutures); // 모든 비동기 작업이 완료될 때까지 기다림

        // 작성 시간을 기준으로 내림차순 정렬
        memos.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));

        print(datas); // 모든 작업 완료 후 출력
      } else {
        print('Failed to load memos: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memos: $e');
    }
  }

  Future<void> _fetchMemoDetails(String memoId) async {
    final url = Uri.parse('$SERVER_IP/memo/$memoId/data');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> memoData = json.decode(response.body);
        int originalIndex = -1;

        // memos 리스트에서 memo_id에 해당하는 메모를 찾아 originalIndex를 구함
        for (var item in memos) {
          if (item['memo_id'] == memoId) {
            originalIndex = memos.indexOf(item);
            break;
          }
        }

        if (originalIndex != -1) {
          // 데이터를 추가하기 전에 해당 메모에 대한 데이터를 초기화
          datas.removeWhere(
              (data) => data['originalIndex'] == originalIndex.toString());

          List<Map<String, dynamic>> memoItems = [];

          for (var item in memoData) {
            memoItems.add({
              'memo_id': item['memo_id'],
              'data_id': item['data_id'],
              'format': item['format'],
            });
          }

          datas.add({
            'originalIndex': originalIndex.toString(),
            'data': memoItems,
          });

          setState(() {}); // 여기에서 상태를 업데이트
        }
      } else {
        print('Failed to load memo datas: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memo datas: $e');
    }
  }

  void _showMenu(BuildContext context, int index) {
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
                leading: Icon(Icons.copy),
                title: Text('복사'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: memos[index]['text']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('메모가 클립보드에 복사되었습니다.')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('공유'),
                onTap: () {
                  Navigator.pop(context);
                  _showFriendSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('삭제'),
                onTap: () {
                  String memoId = memos[index]['memo_id'];
                  setState(() {
                    memos.removeAt(index);
                    _deleteMemoFromServer(memoId);
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

  Future<void> _showFriendSelectionDialog() async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      List<Map<String, String>> friends = data
          .map<Map<String, String>>((friend) => {
                'user_name': friend['friend_name'],
                'user_id': friend['friend_id'],
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
                itemBuilder: (context, friendIndex) {
                  return ListTile(
                    title: Text(friends[friendIndex]['user_name']!),
                    onTap: () {
                      Navigator.pop(context);
                      //_shareMemoWithFriend(friends[index]['user_id']!, index);
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

  Future<void> _shareMemoWithFriend(String friendUserId, int memoId) async {
    final url = Uri.parse('$SERVER_IP/send-memo');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'sourceUserId': USER_ID,
        'targetUserId': friendUserId,
        'memo_id': memoId,
      }),
    );

    if (response.statusCode == 200) {
      print('메모 공유 성공');
      _showMessage('메모가 성공적으로 공유되었습니다.');
    } else {
      print('$USER_ID, $friendUserId, $memoId');
      print('메모 공유 실패: ${response.statusCode}');
      _showMessage('메모 공유에 실패했습니다.');
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
      // 1. memos 리스트를 timestamp를 기준으로 내림차순으로 정렬
      memos.sort((a, b) {
        if (a['isPinned'] && !b['isPinned']) {
          return -1;
        } else if (!a['isPinned'] && b['isPinned']) {
          return 1;
        } else {
          return b['timestamp'].compareTo(a['timestamp']);
        }
      });

      // 2. 정렬된 memos 리스트에 따라 datas 리스트를 재정렬
      datas.sort((a, b) {
        int indexA = memos.indexWhere(
            (memo) => memo['memo_id'] == a['data'].first['memo_id']);
        int indexB = memos.indexWhere(
            (memo) => memo['memo_id'] == b['data'].first['memo_id']);

        // indexA와 indexB를 비교하여 datas 리스트를 memos 리스트의 순서에 맞게 정렬
        return indexA.compareTo(indexB);
      });

      // 3. 정렬된 memos 리스트의 originalIndex를 0부터 다시 매깁니다.
      for (int i = 0; i < memos.length; i++) {
        memos[i]['originalIndex'] = i;
      }

      // 4. datas 리스트의 originalIndex도 memos 리스트와 일치하도록 업데이트합니다.
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
        _deleteMemoFromServer(memoId);
      });
      selectedMemos.clear();
      isSelectionMode = false;
    });
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

  Future<String?> _getData(String dataId) async {
    final url = Uri.parse("$SERVER_IP/data/$dataId/file");
    print(url);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: isSelectionMode ? Text('${selectedMemos.length}개 선택됨') : null,
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
                onPressed: _showFriendSelectionDialog,
              ),
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: _deleteSelectedMemos,
              ),
            ],
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('token');
                await prefs.remove('userId');

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Login()),
                );
              },
            ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PopupMenuButton<int>(
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
                ],
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
                  itemCount: memos.length,
                  itemBuilder: (context, index) {
                    bool isSelected = selectedMemos.contains(index);

                    // 메모의 데이터 불러오기
                    List<Map<String, dynamic>> memoDatas = datas
                        .where(
                            (data) => data['originalIndex'] == index.toString())
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
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.grey),
                              color: memos[index]['color'] ?? Colors.white,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 메모에 포함된 데이터들을 출력
                                  for (var data in memoDatas) ...[
                                    if (data['format'] == 'txt')
                                      FutureBuilder<String?>(
                                        future: _getData(data['data_id']),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.done) {
                                            if (snapshot.hasData) {
                                              return Text(
                                                snapshot.data!,
                                                style: TextStyle(
                                                  fontSize: 16.0,
                                                ),
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              );
                                            } else {
                                              return Text('데이터를 불러올 수 없습니다.');
                                            }
                                          } else {
                                            return CircularProgressIndicator();
                                          }
                                        },
                                      ),
                                    if (data['format'] != 'txt' &&
                                        data['format'] != null)
                                      FutureBuilder<Uint8List?>(
                                        future: _getImage(data['data_id']),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.done) {
                                            if (snapshot.hasData) {
                                              return AspectRatio(
                                                aspectRatio: 1,
                                                child: Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                ),
                                              );
                                            } else {
                                              return Text('이미지를 불러올 수 없습니다.');
                                            }
                                          } else {
                                            return CircularProgressIndicator();
                                          }
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (memos[index]['isPinned'])
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
              // 모든 필드가 null이 아님을 보장
              result['isPinned'] = false; // 새로운 메모는 기본적으로 고정되지 않음
              memos.add(result as Map<String, dynamic>); // 명시적으로 타입을 캐스팅
            });

            // 작성 시간을 기준으로 내림차순 정렬
            memos.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
            _sortMemos();
          }

          _fetchMemos(); // 서버에서 최신 데이터 불러오기
          _sortMemos();
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
