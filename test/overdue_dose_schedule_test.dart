import 'package:flutter_test/flutter_test.dart';
import 'package:med_app/services/overdue_dose_schedule.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location saoPaulo;

  setUpAll(() {
    tzdata.initializeTimeZones();
    saoPaulo = tz.getLocation('America/Sao_Paulo');
  });

  test('schedules the overdue alert after the grace period today', () {
    final schedule = OverdueDoseSchedule.calculate(
      now: tz.TZDateTime(saoPaulo, 2026, 11, 18, 8, 14),
      time: '08:00',
      gracePeriod: const Duration(minutes: 15),
    );

    expect(schedule, isNotNull);
    expect(
      schedule!.scheduledDate,
      tz.TZDateTime(saoPaulo, 2026, 11, 18, 8, 15),
    );
    expect(schedule.shouldNotifyImmediately, isFalse);
  });

  test('catches up immediately when the overdue time has already passed', () {
    final schedule = OverdueDoseSchedule.calculate(
      now: tz.TZDateTime(saoPaulo, 2026, 11, 18, 8, 16),
      time: '08:00',
      gracePeriod: const Duration(minutes: 15),
    );

    expect(schedule, isNotNull);
    expect(schedule!.shouldNotifyImmediately, isTrue);
    expect(
      schedule.scheduledDate,
      tz.TZDateTime(saoPaulo, 2026, 11, 19, 8, 15),
    );
  });

  test('does not repeat a catch-up notification already handled today', () {
    final schedule = OverdueDoseSchedule.calculate(
      now: tz.TZDateTime(saoPaulo, 2026, 11, 18, 8, 16),
      time: '08:00',
      gracePeriod: const Duration(minutes: 15),
      lastHandledDateKey: '2026-11-18',
    );

    expect(schedule, isNotNull);
    expect(schedule!.shouldNotifyImmediately, isFalse);
    expect(
      schedule.scheduledDate,
      tz.TZDateTime(saoPaulo, 2026, 11, 19, 8, 15),
    );
  });

  test('rejects invalid dose times', () {
    expect(
      OverdueDoseSchedule.calculate(
        now: tz.TZDateTime(saoPaulo, 2026, 11, 18, 8),
        time: '25:00',
        gracePeriod: const Duration(minutes: 15),
      ),
      isNull,
    );
  });
}
