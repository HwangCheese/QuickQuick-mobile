import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

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
    // Temporary event data
    _events = {
      DateTime.utc(2024, 7, 27): ['오후 3시 교수님 미팅', '오후 5시 팀 회의', '오후 10시 회식'],
      DateTime.utc(2024, 7, 28): ['오후 7시 동아리 회식', '오전 2시 개인 공부'],
    };
  }

  List<String> _getEventsForDay(DateTime day) {
    return _events[day] ?? [];
  }

  List<String> _sortEvents(List<String> events) {
    events.sort((a, b) {
      final aTime = _convertTo24HourFormat(a.split(' ')[0], a.split(' ')[1]);
      final bTime = _convertTo24HourFormat(b.split(' ')[0], b.split(' ')[1]);
      return aTime.compareTo(bTime);
    });
    return events;
  }

  int _convertTo24HourFormat(String period, String time) {
    final hour = int.parse(time.split('시')[0]);
    if (period == '오후' && hour != 12) {
      return hour + 12;
    } else if (period == '오전' && hour == 12) {
      return 0;
    }
    return hour;
  }

  @override
  Widget build(BuildContext context) {
    final events = _sortEvents(_getEventsForDay(_selectedDay ?? _focusedDay));

    return Scaffold(
      appBar: AppBar(
        title: Text('캘린더'),
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
                titleTextStyle: TextStyle(fontSize: 23.0), // 연, 월 글씨 크기 설정
                headerMargin:
                    const EdgeInsets.only(bottom: 30.0), // 헤더와 날짜 사이 간격
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
                  _focusedDay = focusedDay; // update `_focusedDay` here as well
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue, // Marker color
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
                  border: Border.all(color: Color(0xFFBBDEFB), width: 1.5),
                ),
                todayTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.blue[300],
                  shape: BoxShape.circle,
                ),
                cellMargin:
                    const EdgeInsets.symmetric(vertical: 4.0), // 날짜 셀 간격
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final parts = event.split(' ');
                  final period = parts[0];
                  final time = parts[1];
                  final description = parts.sublist(2).join(' ');
                  final formattedTime = _convertTo24HourFormat(period, time);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Row(
                      children: [
                        Text(
                          '$formattedTime시',
                          style: TextStyle(
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
