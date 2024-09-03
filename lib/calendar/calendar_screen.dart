import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  static void addEvent(BuildContext context, DateTime date, String event) {
    final _CalendarScreenState? state =
        context.findAncestorStateOfType<_CalendarScreenState>();
    state?._addEvent(date, event);
  }

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
    _events = {
      DateTime.utc(2024, 7, 27): ['오후 3시 교수님 미팅', '오후 5시 팀 회의', '오후 10시 회식'],
      DateTime.utc(2024, 7, 28): ['오후 7시 동아리 회식', '오전 2시 개인 공부'],
    };
  }

  void _addEvent(DateTime date, String event) {
    setState(() {
      final localDate = DateTime(date.year, date.month, date.day);
      if (_events.containsKey(localDate)) {
        _events[localDate]!.add(event);
      } else {
        _events[localDate] = [event];
      }
      // Optional: Sort events after adding
      _events[localDate] = _sortEvents(_events[localDate]!);
    });
  }

  List<String> _getEventsForDay(DateTime day) {
    final localDate = DateTime(day.year, day.month, day.day);
    return _events[localDate] ?? [];
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

  String _formatTime(int hour) {
    final period = hour >= 12 ? '오후' : '오전';
    final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$period $formattedHour시';
  }

  @override
  Widget build(BuildContext context) {
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('캘린더'),
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
                  final parts = event.split(' ');
                  final period = parts[0];
                  final time = parts[1];
                  final description = parts.sublist(2).join(' ');
                  final hour = _convertTo24HourFormat(period, time);
                  final formattedTime = _formatTime(hour);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Row(
                      children: [
                        Text(
                          formattedTime,
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
