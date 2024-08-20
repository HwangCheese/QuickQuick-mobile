import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sticker_memo/globals.dart';

class FriendsListScreen extends StatefulWidget {
  @override
  _FriendsListScreenState createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  List<Map<String, String>> friends = [];
  List<Map<String, String>> filteredFriends = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterFriends);
    _fetchFriends();
  }

  void _filterFriends() {
    setState(() {
      filteredFriends = friends
          .where((friend) =>
              friend['user_name'] != null &&
              friend['user_name']!
                  .toLowerCase()
                  .contains(_searchController.text.toLowerCase()))
          .toList();
    });
  }

  Future<void> _fetchFriends() async {
    final response = await http.get(Uri.parse('$SERVER_IP/friends/$USER_NAME'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      print(data);
      setState(() {
        friends = data
            .map<Map<String, String>>((friend) => {
                  'user_name': friend['friend_name'],
                })
            .toList();
        filteredFriends = friends;
      });
    } else {
      _showMessage('친구 목록을 불러오는 데 실패했습니다.');
    }
  }

  Future<void> _refreshFriends() async {
    await _fetchFriends();
  }

  Future<void> _addFriend(String friendUserName) async {
    print('친구 이름: $friendUserName');
    final response = await http.post(
      Uri.parse('${SERVER_IP}/friend'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'user_name': USER_NAME,
        'friend_user_name': friendUserName,
      }),
    );

    if (response.statusCode == 201) {
      // 친구 추가 성공 후, 친구 목록을 새로고침하여 UI를 즉시 업데이트
      print('친구 추가 성공');
      await _fetchFriends();
    } else {
      _showMessage('친구 추가 실패: ${json.decode(response.body)['error']}');
    }
  }

  Future<void> _deleteFriend(String friendUserId) async {
    final url = Uri.parse('${SERVER_IP}/friend');
    final response = await http.delete(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': USER_ID,
        'friend_user_id': friendUserId,
      }),
    );

    if (response.statusCode == 200) {
      setState(() {
        friends.removeWhere((friend) => friend['user_id'] == friendUserId);
        filteredFriends = friends;
      });
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

  void _showDeleteFriendDialog(String friendUserId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('친구 삭제'),
          content: Text('친구를 삭제합니다'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                _deleteFriend(friendUserId);
                Navigator.of(context).pop();
              },
              child: Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('친구 목록'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshFriends,
        child: Column(
          children: <Widget>[
            SizedBox(height: 60.0), // 검색창을 아래로 내리기 위한 여백
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0), // 검색창과 리스트 사이의 간격
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '이름 검색',
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
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredFriends.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(filteredFriends[index]['user_name']!),
                    onLongPress: () {
                      _showDeleteFriendDialog(
                          filteredFriends[index]['user_id']!);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddFriendDialog();
        },
        child: Icon(Icons.add),
        backgroundColor: Color(0xFFCDE9FF), // 버튼 배경 색상
        shape: CircleBorder(), // 버튼 모양을 원으로 설정
        elevation: 2.0, // 그림자 효과
      ),
    );
  }

  void _showAddFriendDialog() {
    final TextEditingController _newFriendController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('친구 추가'),
          content: TextField(
            controller: _newFriendController,
            decoration: InputDecoration(hintText: '친구 이름으로 검색하세요'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                if (_newFriendController.text.isNotEmpty) {
                  _addFriend(_newFriendController.text);
                  Navigator.of(context).pop();
                }
              },
              child: Text('추가'),
            ),
          ],
        );
      },
    );
  }
}
