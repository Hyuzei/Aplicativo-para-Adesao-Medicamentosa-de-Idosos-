import 'package:timezone/timezone.dart' as tz;

const caregiverOverdueGracePeriod = Duration(minutes: 15);

class OverdueDoseSchedule {
  const OverdueDoseSchedule({
    required this.scheduledDate,
    required this.shouldNotifyImmediately,
    required this.handledDateKey,
  });

  final tz.TZDateTime scheduledDate;
  final bool shouldNotifyImmediately;
  final String handledDateKey;

  static OverdueDoseSchedule? calculate({
    required tz.TZDateTime now,
    required String time,
    required Duration gracePeriod,
    String? lastHandledDateKey,
  }) {
    final parts = time.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || hour < 0 || hour > 23) return null;
    if (minute == null || minute < 0 || minute > 59) return null;

    final todayDue = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).add(gracePeriod);
    final isOverdue = !todayDue.isAfter(now);
    final todayKey = _dateKey(now);

    return OverdueDoseSchedule(
      scheduledDate: isOverdue
          ? todayDue.add(const Duration(days: 1))
          : todayDue,
      shouldNotifyImmediately: isOverdue && lastHandledDateKey != todayKey,
      handledDateKey: todayKey,
    );
  }

  static String _dateKey(tz.TZDateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
