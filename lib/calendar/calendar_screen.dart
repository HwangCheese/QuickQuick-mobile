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
    // 임시 일정 데이터 추가
    _events = {
      DateTime.utc(2024, 7, 27): ['3시 교수님 미팅'],
      DateTime.utc(2024, 7, 28): ['7시 동아리 회식'],
    };
  }

  List<String> _getEventsForDay(DateTime day) {
    return _events[day] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('캘린더'),
      ),
      body: Padding(
        padding: const EdgeInsets.only(
            top: 50.0, left: 16.0, right: 16.0, bottom: 16.0),
        child: Column(
          children: [
            TableCalendar(
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                leftChevronVisible: true,
                rightChevronVisible: true,
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
                          color: Colors.blue, // 마커 색상
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
              ),
            ),
            const SizedBox(height: 20),
            ..._getEventsForDay(_selectedDay ?? _focusedDay).map(
              (event) => ListTile(
                title: Text(event),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
