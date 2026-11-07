import '../data/local/sindar_database.dart';

/// Recognize earned rental revenue without double posting; legacy contracts
/// were booked in full and are excluded from this routine.
class RentalAccrualService {
  const RentalAccrualService();

  Future<void> accrue({DateTime? asOf}) async {
    final instant = (asOf ?? DateTime.now()).toUtc();
    final db = await SindarDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT r.id, r.document_id, r.start_at, r.due_at, '
        'r.earned_amount, d.total FROM equipment_rentals r '
        'JOIN documents d ON d.id = r.document_id '
        "WHERE r.billing_unit != 'legacy' AND d.status != 'void' "
        'AND r.earned_amount < d.total - 0.005',
      );
      for (final row in rows) {
        final start = DateTime.parse(row['start_at'] as String).toUtc();
        final end = DateTime.parse(row['due_at'] as String).toUtc();
        final total = (row['total'] as num).toDouble();
        final recorded = (row['earned_amount'] as num).toDouble();
        if (!instant.isAfter(start)) continue;
        final earned = instant.isBefore(end)
            ? double.parse((total * instant.difference(start).inSeconds /
                end.difference(start).inSeconds).toStringAsFixed(2))
            : total;
        final delta = double.parse((earned - recorded).toStringAsFixed(2));
        if (delta <= 0.005) continue;
        final at = instant.toIso8601String();
        final entry = await txn.insert('journal_entries', {
          'date': at, 'reference_type': 'equipment_rental_accrual',
          'reference_id': row['document_id'],
          'description': 'إيراد تأجير مكتسب - عقد ${row['document_id']}',
          'created_at': at,
        });
        await txn.insert('journal_lines', {
          'entry_id': entry, 'account_code': '2106',
          'debit': delta, 'credit': 0,
        });
        await txn.insert('journal_lines', {
          'entry_id': entry, 'account_code': '4104',
          'debit': 0, 'credit': delta,
        });
        await txn.update('equipment_rentals', {'earned_amount': earned},
            where: 'id = ?', whereArgs: [row['id']]);
      }
    });
  }
}
