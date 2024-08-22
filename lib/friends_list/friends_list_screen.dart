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
      try {
        // 서버에서 받은 데이터의 구조 확인
        final List<dynamic> data = json.decode(response.body);

        setState(() {
          // 친구 목록 업데이트
          friends = data.map<Map<String, String>>((friend) {
            // 'friend_name_set' 필드가 실제 서버 데이터에 맞는지 확인 필요
            return {
              'user_name': friend['friend_name_set'] ?? '',
            };
          }).toList();

          filteredFriends = List.from(friends); // filteredFriends 갱신
        });
      } catch (e) {
        print('JSON Parsing Error: $e');
        _showMessage('서버 응답 처리 중 오류 발생');
      }
    } else {
      // 오류 처리
      _showMessage('친구 목록을 불러오는 데 실패했습니다.');
    }
  }

  Future<void> _refreshFriends() async {
    await _fetchFriends();
  }

  Future<void> _addFriend(String friendUserName) async {
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
      await _fetchFriends();
    } else {
      _showMessage('친구 추가 실패: ${json.decode(response.body)['error']}');
    }
  }

  Future<void> _updateFriendName(
      String oldFriendUserName, String newFriendUserName) async {
    final url = Uri.parse('${SERVER_IP}/friend/name');

    final requestBody = jsonEncode({
      'user_name': USER_NAME,
      'friend_user_name': oldFriendUserName,
      'new_friend_name': newFriendUserName,
    });

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    try {
      if (response.statusCode == 200) {
        setState(() {
          // 친구 이름을 업데이트한 후, 데이터 상태를 갱신
          final friendIndex = friends
              .indexWhere((friend) => friend['user_name'] == oldFriendUserName);
          if (friendIndex != -1) {
            friends[friendIndex]['user_name'] = newFriendUserName;
            filteredFriends = List.from(friends); // UI 업데이트를 위해 새 리스트로 설정
          }
        });
      } else {
        final responseBody = json.decode(response.body);
        final errorMessage = responseBody['error'] ?? '알 수 없는 오류 발생';
        _showMessage('친구 이름 수정 실패: $errorMessage');
      }
    } catch (e) {
      print('JSON Parsing Error: $e');
      _showMessage('서버 응답 처리 중 오류 발생');
    }
  }

  Future<void> _deleteFriend(String friendUserName) async {
    final url = Uri.parse('${SERVER_IP}/friend');

    final requestBody = jsonEncode({
      'user_name': USER_NAME,
      'friend_name_set': friendUserName, // friend_name_set으로 수정
    });

    final response = await http.delete(
      url,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      setState(() {
        friends.removeWhere((friend) => friend['user_name'] == friendUserName);
        filteredFriends = friends; // UI 업데이트
      });
    } else {
      final errorMessage =
          json.decode(response.body)['error'] ?? '알 수 없는 오류 발생';
      _showMessage('친구 삭제 실패: $errorMessage');
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

  void _showActionDialog(String friendUserName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('친구 옵션'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showUpdateFriendDialog(friendUserName);
              },
              child: Text('수정'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDeleteFriendDialog(friendUserName);
              },
              child: Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateFriendDialog(String oldFriendUserName) {
    final TextEditingController _newFriendController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('친구 이름 수정'),
          content: TextField(
            controller: _newFriendController,
            decoration: InputDecoration(hintText: '새로운 친구 이름'),
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
                  _updateFriendName(
                      oldFriendUserName, _newFriendController.text);
                  Navigator.of(context).pop();
                }
              },
              child: Text('수정'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteFriendDialog(String friendUserName) {
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
                _deleteFriend(friendUserName);
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
                      _showActionDialog(filteredFriends[index]['user_name']!);
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
