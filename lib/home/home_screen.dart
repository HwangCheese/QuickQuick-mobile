import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    searchResults = memos; // 초기 검색 결과는 전체 메모로 설정
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
                  // 복사 기능 추가 가능
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
                  setState(() {
                    memos.removeAt(index);
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
          initialColor: Color(memos[index]['color']),
        ),
      ),
    );
    if (result != null && result['text'].isNotEmpty) {
      setState(() {
        memos[index] = result;
        _searchMemo(_controller.text); // 업데이트된 메모로 검색 결과 갱신
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(
            top: 150.0, left: 16.0, right: 16.0, bottom: 16.0),
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
                      // 선택 기능 추가 가능
                    } else if (result == 1) {
                      _navigateToCalendar(context);
                    } else if (result == 2) {
                      _navigateToFriendsList(context);
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
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
                hintText: '검색…',
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
              onSubmitted: (text) {
                _searchMemo(text);
              },
            ),
            SizedBox(height: 16.0),
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // 한 줄에 3개의 메모를 표시
                  childAspectRatio: 1, // 정사각형으로 만들기 위해 1:1 비율 설정
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: searchResults.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () =>
                        _editMemo(context, index), // 메모를 클릭하면 편집 화면으로 이동
                    onLongPress: () => _showMenu(context, index),
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Color(searchResults[index]['color']),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: Center(
                            child: Text(
                              searchResults[index]['text'],
                              style: TextStyle(fontSize: 16.0),
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
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
