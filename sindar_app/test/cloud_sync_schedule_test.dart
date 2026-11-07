import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/src/services/free_google_drive_sync_service.dart';

void main() {
  test('cloud schedule storage values are stable', () {
    expect(
      CloudSyncSchedule.fromStorage('automatic'),
      CloudSyncSchedule.automatic,
    );
    expect(
      CloudSyncSchedule.fromStorage('daily'),
      CloudSyncSchedule.daily,
    );
    expect(
      CloudSyncSchedule.fromStorage('weekly'),
      CloudSyncSchedule.weekly,
    );
    expect(
      CloudSyncSchedule.fromStorage(null),
      CloudSyncSchedule.manual,
    );
    expect(
      CloudSyncSchedule.fromStorage('unknown'),
      CloudSyncSchedule.manual,
    );
  });

  test('background frequencies respect Android WorkManager minimums', () {
    expect(
      CloudSyncSchedule.automatic.frequency,
      const Duration(hours: 6),
    );
    expect(
      CloudSyncSchedule.daily.frequency,
      const Duration(hours: 24),
    );
    expect(
      CloudSyncSchedule.weekly.frequency,
      const Duration(days: 7),
    );
    expect(CloudSyncSchedule.manual.frequency, isNull);
  });
}
