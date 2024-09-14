import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../globals.dart';
import '../write_memo/write_memo_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<String>> _events = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadEvents();
    });
  }

  Future<void> _loadEvents() async {
    try {
      final response =
          await http.get(Uri.parse('$SERVER_IP/events/' + USER_ID));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _events = {};
          for (var item in data) {
            final datetime =
                DateTime.parse(item['event_datetime']).toLocal(); // UTC를 로컬로 변환
            final localDate =
                DateTime(datetime.year, datetime.month, datetime.day);
            final time = DateFormat('HH:mm').format(datetime);
            final description = item['description'];
            if (_events[localDate] == null) {
              _events[localDate] = [];
            }
            _events[localDate]!.add('$time - $description');
          }
        });
      } else {
        throw Exception('Failed to load events: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading events: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load events: $e')),
      );
    }
  }

  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    print('Retrieved user_id: $userId'); // 디버깅
    return userId;
  }

  Future<void> addEvent(DateTime eventDateTime, String description) async {
    // Format the event date and time
    String eventDateTimeString =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(eventDateTime);

    // Prepare data for HTTP POST request
    Map<String, String> eventData = {
      'user_id': USER_ID,
      'event_datetime': eventDateTimeString,
      'description': description,
    };

    // Send HTTP POST request
    try {
      var response = await http.post(
        Uri.parse('$SERVER_IP/events'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(eventData),
      );

      if (response.statusCode == 201) {
        print('Event added successfully: ${response.body}');
        await _loadEvents();
      } else {
        print('Failed to add event: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Error occurred: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('일정 추가 중 오류 발생: $e')),
      );
    }
  }

  Future<void> _deleteEvent(DateTime date, String description) async {
    try {
      // 이벤트 ID를 가져오는 로직 추가 (예: getEventIdFromDescription)
      final eventId = await getEventIdFromDescription(description);
      if (eventId == null) {
        throw Exception('이벤트 ID를 찾을 수 없습니다.');
      }

      final response = await http.delete(
        Uri.parse('$SERVER_IP/events/$eventId'),
      );

      if (response.statusCode == 200) {
        print('Event deleted successfully');
        await _loadEvents(); // 이벤트 삭제 후 다시 로드
      } else {
        throw Exception('Failed to delete event: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting event: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete event: $e')),
      );
    }
  }

  Future<void> _updateEvent(
      DateTime date, String oldDescription, String newDescription) async {
    try {
      // 이벤트 ID를 가져오는 로직 추가 (예: getEventIdFromDescription)
      final eventId = await getEventIdFromDescription(oldDescription);
      if (eventId == null) {
        throw Exception('이벤트 ID를 찾을 수 없습니다.');
      }

      final formattedDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(date);

      final response = await http.put(
        Uri.parse('$SERVER_IP/events/$eventId'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'event_datetime': formattedDateTime,
          'description': newDescription,
        }),
      );

      if (response.statusCode == 200) {
        print('Event updated successfully');
        await _loadEvents(); // 이벤트 업데이트 후 다시 로드
      } else {
        throw Exception('Failed to update event: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating event: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update event: $e')),
      );
    }
  }

  Future<String?> getEventIdFromDescription(String description) async {
    try {
      final response =
          await http.get(Uri.parse('$SERVER_IP/events/' + USER_ID));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        for (var item in data) {
          // Assume the 'description' and 'event_id' keys exist in the API response
          if (item['description'] == description) {
            return item['event_id']; // Return the matched event ID
          }
        }
        return null; // No matching description found
      } else {
        throw Exception('Failed to fetch events: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching event ID: $e');
      return null;
    }
  }

  bool _isEventLine(String line) {
    RegExp pattern = RegExp(r'(\d{1,2})월 (\d{1,2})일 (\d{1,2})시\s+(.+)');
    return pattern.hasMatch(line);
  }

  void _showAddEventDialog() {
    final TextEditingController descriptionController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime selectedDate = _focusedDay;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('새 일정 추가'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 400, // 대화 상자의 최대 높이를 설정합니다.
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Wrap TextField with Flexible
                      Flexible(
                        child: TextField(
                          controller: descriptionController,
                          decoration: InputDecoration(labelText: '일정 설명'),
                          maxLines: null, // 여러 줄 입력 가능
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '날짜: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              final DateTime? pickedDate = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2101),
                              );
                              if (pickedDate != null &&
                                  pickedDate != selectedDate) {
                                setState(() {
                                  selectedDate = pickedDate;
                                });
                              }
                            },
                            child: Text('날짜 선택'),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '시간: ${selectedTime.format(context)}',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              final TimeOfDay? pickedTime =
                                  await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (pickedTime != null &&
                                  pickedTime != selectedTime) {
                                setState(() {
                                  selectedTime = pickedTime;
                                });
                              }
                            },
                            child: Text('시간 선택'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    final eventDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    addEvent(eventDateTime, descriptionController.text);
                    Navigator.of(context).pop();
                  },
                  child: Text('추가'),
                ),
              ],
            );
          },
        );
      },
    );
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
              },
            ),
            TextButton(
              child: Text('추가'),
              onPressed: () {
                Navigator.of(context).pop();
                _processEventLine(line); // _processEventLine 직접 호출
              },
            ),
          ],
        );
      },
    );
  }

  void _processEventLine(String line) {
    RegExp pattern = RegExp(r'(\d{1,2})월 (\d{1,2})일 (\d{1,2})시\s+(.+)');
    Match? match = pattern.firstMatch(line);

    if (match != null) {
      int month = int.parse(match.group(1)!);
      int day = int.parse(match.group(2)!);
      String eventDescription = match.group(3)!;

      // Set year to 2024 (or the current year if you want)
      DateTime eventDate = DateTime(2024, month, day);

// Debugging statement
      print(
          'Processed Event - Date: $eventDate, Description: $eventDescription');

      // Add the event to the calendar
      addEvent(eventDate, eventDescription);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('일정 형식이 올바르지 않습니다.')),
      );
    }
  }

  List<String> _getEventsForDay(DateTime day) {
    final localDate = DateTime(day.year, day.month, day.day);
    return _events[localDate]?.map((event) {
          final parts = event.split(' - ');
          final time = parts[0] != "00:00:00" ? parts[0].substring(0, 5) : '';
          final description = parts[1];
          return time.isNotEmpty ? '$time - $description' : description;
        }).toList() ??
        [];
  }

  Future<void> _openWriteMemoScreen() async {
    final memo = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WriteMemoScreen()),
    );

    if (memo != null && _isEventLine(memo)) {
      _showEventConfirmationDialog(memo);
    }
  }

  void _showEventOptionsDialog(DateTime date, String eventDescription) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('일정 옵션'),
          content: Text('일정을 수정하거나 삭제하시겠습니까?\n$eventDescription'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditEventDialog(date, eventDescription);
              },
              child: Text('수정'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteEvent(date, eventDescription);
              },
              child: Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  void _showEditEventDialog(DateTime date, String oldDescription) {
    TextEditingController _controller =
        TextEditingController(text: oldDescription);

    TimeOfDay selectedTime = TimeOfDay.fromDateTime(date);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('일정 수정'),
              content: SizedBox(
                width: double.maxFinite, // Ensure the dialog uses full width
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _controller,
                      decoration: InputDecoration(labelText: '일정 내용'),
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '시간: ${selectedTime.format(context)}',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () async {
                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                            );
                            if (pickedTime != null &&
                                pickedTime != selectedTime) {
                              setState(() {
                                selectedTime = pickedTime;
                              });
                            }
                          },
                          child: Text('시간 선택'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    final updatedDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    Navigator.of(context).pop();
                    _updateEvent(
                        updatedDateTime, oldDescription, _controller.text);
                  },
                  child: Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('캘린더'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddEventDialog, // "+" 버튼 클릭 시 다이얼로그 열기
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(
            top: 50.0, left: 16.0, right: 16.0, bottom: 16.0),
        child: Column(
          children: <Widget>[
            TableCalendar(
              locale: 'ko_KR',
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                leftChevronVisible: true,
                rightChevronVisible: true,
                titleTextStyle: const TextStyle(fontSize: 23.0),
                headerMargin: const EdgeInsets.only(bottom: 30.0),
              ),
              firstDay: DateTime.utc(2010, 10, 16),
              lastDay: DateTime.utc(2030, 3, 14),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) {
                return isSameDay(_selectedDay, day);
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              eventLoader: _getEventsForDay,
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  if (events.isNotEmpty) {
                    return Positioned(
                      bottom: 1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                        ),
                      ),
                    );
                  }
                  return null;
                },
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0xFFBBDEFB), width: 1.5),
                ),
                todayTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.blue[300],
                  shape: BoxShape.circle,
                ),
                cellMargin: const EdgeInsets.symmetric(vertical: 4.0),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final parts = event.split(' - ');
                  final time = parts[0];
                  final description = parts[1];

                  return GestureDetector(
                    onLongPress: () {
                      _showEventOptionsDialog(
                          _selectedDay ?? _focusedDay, description);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Row(
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(description),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
