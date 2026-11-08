import '../data/local/sindar_database.dart';

/// Idempotent accrual. For long leases, entries are booked at month-end as
/// needed, even when the app was offline at that time.
class RentalAccrualService {
  const RentalAccrualService();

  Future<void> accrue({DateTime? asOf}) async {
    final instant = (asOf ?? DateTime.now()).toUtc();
    final db = await SindarDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT r.id, r.document_id, r.start_at, r.due_at, '
        'r.earned_amount, d.subtotal FROM equipment_rentals r '
        'JOIN documents d ON d.id = r.document_id '
        "WHERE r.billing_unit != 'legacy' AND d.status != 'void' "
        'AND r.earned_amount < d.subtotal - 0.005',
      );
      for (final row in rows) {
        final start = DateTime.parse(row['start_at'] as String).toUtc();
        final due = DateTime.parse(row['due_at'] as String).toUtc();
        final total = (row['subtotal'] as num).toDouble();
        var recorded = (row['earned_amount'] as num).toDouble();
        if (!instant.isAfter(start) || !due.isAfter(start)) continue;

        double earnedAt(DateTime at) {
          if (!at.isAfter(start)) return 0;
          if (!at.isBefore(due)) return total;
          final elapsed = at.difference(start).inSeconds;
          final duration = due.difference(start).inSeconds;
          return double.parse((total * elapsed / duration).toStringAsFixed(2));
        }

        Future<void> post(DateTime accountingDate) async {
          final target = earnedAt(accountingDate);
          final delta = double.parse((target - recorded).toStringAsFixed(2));
          if (delta <= 0.005) return;
          final date = accountingDate.toIso8601String();
          final entry = await txn.insert('journal_entries', {
            'date': date, 'reference_type': 'equipment_rental_accrual',
            'reference_id': row['document_id'],
            'description': 'إيراد إيجار مكتسب - عقد ${row['document_id']}',
            'created_at': instant.toIso8601String(),
          });
          await txn.insert('journal_lines', {
            'entry_id': entry, 'account_code': '2106',
            'debit': delta, 'credit': 0,
          });
          await txn.insert('journal_lines', {
            'entry_id': entry, 'account_code': '4104',
            'debit': 0, 'credit': delta,
          });
          recorded = target;
          await txn.update('equipment_rentals',
            {'earned_amount': recorded}, where: 'id = ?', whereArgs: [row['id']]);
        }

        var month = DateTime.utc(start.year, start.month + 1);
        final cutoff = due.isBefore(instant) ? due : instant;
        while (month.isBefore(cutoff)) {
          // Book the final moment of the old month, preserving P&L periods.
          await post(month.subtract(const Duration(microseconds: 1)));
          month = DateTime.utc(month.year, month.month + 1);
        }
        await post(cutoff);
      }
    });
  }
}
