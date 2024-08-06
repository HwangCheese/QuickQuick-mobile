import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data'; // Uint8List를 사용하기 위해 추가
import '../calendar/calendar_screen.dart';
import '../friends_list/friends_list_screen.dart';
import '../write_memo/write_memo_screen.dart';
import 'package:sticker_memo/globals.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> memos = [];
  List<Map<String, dynamic>> searchResults = [];
  bool isSelectionMode = false;
  Set<int> selectedMemos = Set<int>();

  Map<String, Color> colorMap = {
    'pink': Colors.pink[100]!,
    'blue': Colors.blue[100]!,
    'green': Colors.green[100]!,
    'orange': Colors.orange[100]!,
    'yellow': Colors.yellow[100]!,
  };

  @override
  void initState() {
    super.initState();
    _fetchMemos(); // user의 메모 데이터를 가져오는 함수 호출
    searchResults = memos; // 초기 검색 결과는 전체 메모로 설정
  }

  Future<void> _fetchMemos() async {
    final url = Uri.parse('$SERVER_IP/data/$USER_ID');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          memos = data.map((item) {
            return {
              'format': item['format'],
              'text': item['data_txt'],
              'color': colorMap[item['theme']] ?? Colors.white,
              'isPinned': false,
              'dataId': item['dataId'],
              'originalIndex': memos.length,
            };
          }).toList();
          searchResults = memos;
          print(memos);
        });
      } else {
        print('Failed to load memos: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load memos: $e');
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
                  // 공유 기능 추가 가능
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('삭제'),
                onTap: () {
                  String dataId = memos[index]['dataId'];
                  setState(() {
                    memos.removeAt(index);
                    _deleteMemoFromServer(dataId);
                    _searchMemo(_controller.text);
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

  Future<void> _deleteMemoFromServer(String dataId) async {
    if (dataId == null) return;

    final url = Uri.parse('$SERVER_IP/data/$dataId');
    final response = await http.delete(url);

    if (response.statusCode == 200) {
      print('메모 삭제 성공');
      setState(() {
        memos.removeWhere((memo) => memo['dataId'] == dataId);
        searchResults = memos;
      });
    } else {
      print('메모 삭제 실패: ${response.statusCode}');
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
                      // 추가 기능 필요 시 여기에 작성
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

  void _togglePin(int index) {
    setState(() {
      memos[index]['isPinned'] = !memos[index]['isPinned'];
      if (memos[index]['isPinned']) {
        memos[index]['originalIndex'] = index;
      } else {
        int originalIndex = memos[index]['originalIndex'];
        Map<String, dynamic> memo = memos.removeAt(index);
        memos.insert(originalIndex, memo);
      }
      _sortMemos();
      _searchMemo(_controller.text);
    });
  }

  void _sortMemos() {
    memos.sort((a, b) {
      if (a['isPinned'] && !b['isPinned']) {
        return -1;
      } else if (!a['isPinned'] && b['isPinned']) {
        return 1;
      } else {
        return 0;
      }
    });
  }

  void _searchMemo(String text) {
    setState(() {
      if (text.isEmpty) {
        searchResults = memos;
      } else {
        searchResults =
            memos.where((memo) => memo['text'].contains(text)).toList();
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteMemoScreen(
          initialText: memos[index]['text'],
          initialColor: memos[index]['color'],
          initialDataId: memos[index]['dataId'],
        ),
      ),
    );
    if (result != null && result['text'].isNotEmpty) {
      setState(() {
        memos[index] = result;
        _searchMemo(_controller.text);
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
      if (selectedMemos.length == searchResults.length) {
        selectedMemos.clear();
      } else {
        selectedMemos = Set<int>.from(
            List<int>.generate(searchResults.length, (index) => index));
      }
    });
  }

  void _deleteSelectedMemos() {
    setState(() {
      selectedMemos.forEach((index) {
        String dataId = memos[index]['dataId'];
        _deleteMemoFromServer(dataId);
      });
      selectedMemos.clear();
      isSelectionMode = false;
    });
  }

  Future<Uint8List?> _getImage(String id) async {
    final url = Uri.parse("$SERVER_IP/media/$USER_ID/$id");
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
          actions: isSelectionMode
              ? [
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
                ]
              : null,
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
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: Icon(Icons.search),
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
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(
                      color: Color(0xFFE2F1FF), // 에러 상태 테두리 색상
                      width: 3.0, // 테두리 굵기
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(
                      color: Color(0xFFE2F1FF), // 포커스 에러 상태 테두리 색상
                      width: 3.0, // 테두리 굵기
                    ),
                  ),
                ),
                onChanged: (text) {
                  _searchMemo(text); // 검색어가 변경될 때마다 호출
                },
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
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    bool isSelected = selectedMemos.contains(index);
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
                              color:
                                  searchResults[index]['color'] ?? Colors.white,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (searchResults[index]['format'] != 'txt')
                                    FutureBuilder<Uint8List?>(
                                      future: _getImage(
                                          searchResults[index]['dataId']),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.done) {
                                          if (snapshot.hasData) {
                                            return Image.memory(snapshot.data!);
                                          } else {
                                            return Text('이미지를 불러올 수 없습니다.');
                                          }
                                        } else {
                                          return CircularProgressIndicator();
                                        }
                                      },
                                    ),
                                  if (searchResults[index]['text'] != null)
                                    Text(
                                      searchResults[index]['text'],
                                      style: TextStyle(
                                        fontSize: 16.0,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (searchResults[index]['isPinned'])
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
              )
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
          if (result != null && result['text'].isNotEmpty) {
            setState(() {
              result['isPinned'] = false; // 새로운 메모는 기본적으로 고정되지 않음
              result['originalIndex'] = memos.length; // 새로운 메모의 원래 인덱스 설정
              memos.add(result);
              _searchMemo(_controller.text); // 새로운 메모 추가 시 검색 결과 업데이트
            });
          }
          _fetchMemos(); // 서버에서 최신 데이터 불러오기
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
