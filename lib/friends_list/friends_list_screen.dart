import 'package:flutter/material.dart';

class FriendsListScreen extends StatefulWidget {
  @override
  _FriendsListScreenState createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  List<String> friends = ['이동건', '하여린', '윤단비', '전아린'];
  List<String> filteredFriends = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredFriends = friends;
    _searchController.addListener(_filterFriends);
  }

  void _filterFriends() {
    setState(() {
      filteredFriends = friends
          .where((friend) => friend
              .toLowerCase()
              .contains(_searchController.text.toLowerCase()))
          .toList();
    });
  }

  void _addFriend(String newFriend) {
    setState(() {
      friends.add(newFriend);
      filteredFriends = friends;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('친구 목록'),
      ),
      body: Column(
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
                  suffixIcon: Icon(Icons.search, color: Colors.grey), // 검색 아이콘
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredFriends.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(filteredFriends[index]),
                );
              },
            ),
          ),
        ],
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
            decoration: InputDecoration(hintText: '친구 이름'),
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
