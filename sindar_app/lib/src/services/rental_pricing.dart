/// Unit-aware pricing with calendar-based months and years.
enum RentalPeriod {
  hour('hour', 'ساعة'),
  day('day', 'يوم'),
  week('week', 'أسبوع'),
  month('month', 'شهر'),
  year('year', 'سنة');

  const RentalPeriod(this.code, this.label);
  final String code;
  final String label;
}

class RentalQuote {
  const RentalQuote({
    required this.period,
    required this.quantity,
    required this.unitRate,
    required this.start,
    required this.due,
    required this.total,
  });

  final RentalPeriod period;
  final int quantity;
  final double unitRate;
  final DateTime start;
  final DateTime due;
  final double total;

  static RentalQuote create({
    required RentalPeriod period,
    required int quantity,
    required double unitRate,
    required DateTime start,
  }) {
    if (quantity < 1 || quantity > 10000) {
      throw const FormatException('حدد مدة إيجار صحيحة من 1 إلى 10000');
    }
    if (!unitRate.isFinite || unitRate <= 0) {
      throw const FormatException('حدد سعر الإيجار للوحدة المختارة');
    }
    final startUtc = start.toUtc();
    final due = switch (period) {
      RentalPeriod.hour => startUtc.add(Duration(hours: quantity)),
      RentalPeriod.day => startUtc.add(Duration(days: quantity)),
      RentalPeriod.week => startUtc.add(Duration(days: 7 * quantity)),
      RentalPeriod.month => _calendarMonths(startUtc, quantity),
      RentalPeriod.year => _calendarMonths(startUtc, 12 * quantity),
    };
    final total = double.parse((unitRate * quantity).toStringAsFixed(2));
    if (total <= 0 || !total.isFinite || !due.isAfter(startUtc)) {
      throw const FormatException('مدة أو قيمة الإيجار غير صحيحة');
    }
    return RentalQuote(period: period, quantity: quantity, unitRate: unitRate,
      start: startUtc, due: due, total: total);
  }

  static DateTime _calendarMonths(DateTime d, int months) {
    final first = DateTime.utc(d.year, d.month + months, 1);
    final finalDay = DateTime.utc(first.year, first.month + 1, 0).day;
    final day = d.day < finalDay ? d.day : finalDay;
    return DateTime.utc(first.year, first.month, day, d.hour, d.minute,
      d.second, d.millisecond, d.microsecond);
  }

  double earnedThrough(DateTime asOf) {
    final instant = asOf.toUtc();
    if (!instant.isAfter(start)) return 0;
    if (!instant.isBefore(due)) return total;
    final elapsed = instant.difference(start).inSeconds;
    final length = due.difference(start).inSeconds;
    if (length <= 0) return total;
    return double.parse((total * elapsed / length).toStringAsFixed(2));
  }
}
