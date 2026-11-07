import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/src/services/rental_pricing.dart';

void main() {
  test('hours pricing, time and proportional revenue', () {
    final q = RentalQuote.create(
      period: RentalPeriod.hour, quantity: 5, unitRate: 1500,
      start: DateTime.utc(2026, 11, 8, 10),
    );
    expect(q.due, DateTime.utc(2026, 11, 8, 15));
    expect(q.total, 7500);
    expect(q.earnedThrough(DateTime.utc(2026, 11, 8, 12, 30)), 3750);
  });
  test('calendar month clamps January 31', () {
    final q = RentalQuote.create(period: RentalPeriod.month, quantity: 1,
      unitRate: 20000, start: DateTime.utc(2027, 1, 31, 8));
    expect(q.due, DateTime.utc(2027, 2, 28, 8));
  });
  test('leap year annual rental', () {
    final q = RentalQuote.create(period: RentalPeriod.year, quantity: 1,
      unitRate: 100000, start: DateTime.utc(2028, 2, 29));
    expect(q.due, DateTime.utc(2029, 2, 28));
  });
  test('invalid duration and rates are rejected', () {
    expect(() => RentalQuote.create(period: RentalPeriod.day, quantity: 0,
      unitRate: 1, start: DateTime.utc(2026, 1, 1)), throwsFormatException);
    expect(() => RentalQuote.create(period: RentalPeriod.day, quantity: 2,
      unitRate: 0, start: DateTime.utc(2026, 1, 1)), throwsFormatException);
  });
}
