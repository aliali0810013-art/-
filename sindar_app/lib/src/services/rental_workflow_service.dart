import 'package:sqflite/sqflite.dart';

import '../data/local/sindar_database.dart';
import 'rental_pricing.dart';

/// Transactional workflow for rental quotations, contracts, receipts/expenses
/// and equipment return. Equipment is never sold through this service.
class RentalWorkflowService {
  const RentalWorkflowService();

  Future<List<Map<String, Object?>>> equipment() async {
    final db = await SindarDatabase.instance.database;
    return db.query('rental_equipment', orderBy: 'name, code');
  }

  Future<List<Map<String, Object?>>> rentals() async {
    final db = await SindarDatabase.instance.database;
    return db.rawQuery(
      'SELECT r.*, d.number, d.subtotal, d.vat_total, d.total, d.paid_amount, '
      'p.name AS customer_name, p.vat_number AS customer_vat_number, '
      'p.commercial_registration AS customer_cr, e.name AS equipment_name, '
      'e.code AS equipment_code, emp.name AS employee_name, '
      'COALESCE((SELECT SUM(x.amount) FROM rental_expenses x '
      'WHERE x.rental_id=r.id),0) AS expenses_total '
      'FROM equipment_rentals r '
      'JOIN documents d ON d.id=r.document_id '
      'JOIN parties p ON p.id=r.customer_id '
      'JOIN rental_equipment e ON e.id=r.equipment_id '
      'LEFT JOIN employees emp ON emp.id=r.employee_id '
      'ORDER BY r.created_at DESC',
    );
  }

  Future<List<Map<String, Object?>>> quotes() async {
    final db = await SindarDatabase.instance.database;
    return db.rawQuery(
      'SELECT q.*, d.number, d.subtotal, d.vat_total, d.total, '
      'p.name AS customer_name, p.vat_number AS customer_vat_number, '
      'p.commercial_registration AS customer_cr, e.name AS equipment_name, '
      'e.code AS equipment_code, emp.name AS employee_name '
      'FROM rental_quotes q '
      'JOIN documents d ON d.id=q.document_id '
      'JOIN parties p ON p.id=q.customer_id '
      'JOIN rental_equipment e ON e.id=q.equipment_id '
      'LEFT JOIN employees emp ON emp.id=q.employee_id '
      'ORDER BY q.created_at DESC',
    );
  }

  Future<int> createQuote({
    required int equipmentId,
    required int customerId,
    int? employeeId,
    required DateTime start,
    required RentalPeriod period,
    required int quantity,
    required double agreedRate,
    required bool taxInvoice,
    String? notes,
  }) async {
    final db = await SindarDatabase.instance.database;
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final quote = RentalQuote.create(
      period: period, quantity: quantity, unitRate: agreedRate, start: start);
    final taxAllowed = policy.taxModeEnabled;
    final vatRate = taxInvoice && taxAllowed ? .15 : 0.0;
    final net = quote.total;
    final vat = double.parse((net * vatRate).toStringAsFixed(2));
    final gross = net + vat;

    return db.transaction((txn) async {
      final equipment = await txn.query('rental_equipment',
        where: 'id=?', whereArgs: [equipmentId], limit: 1);
      if (equipment.isEmpty) throw const FormatException('المعدة غير موجودة');
      final customer = await txn.query('parties',
        where: "id=? AND type='customer'", whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw const FormatException('العميل غير موجود');
      await _validateEmployee(txn, employeeId);

      final sequence = await _nextSequence(txn, 'rental_quotation');
      final number = 'RQT-${sequence.toString().padLeft(6, '0')}';
      final now = DateTime.now().toUtc().toIso8601String();
      final docId = await txn.insert('documents', {
        'type': 'rental_quotation',
        'number': number,
        'date': now,
                'party_id': customerId,
        'party_name': customer.first['name'],
        'party_vat_number':
            taxAllowed ? customer.first['vat_number'] : null,
        'party_commercial_registration':
            taxAllowed ? customer.first['commercial_registration'] : null,
        'payment_method': 'none',
        'status': 'draft',
        'subtotal': net,
        'vat_total': vat,
        'total': gross,
        'paid_amount': 0,
        'currency_code': policy.currencyCode,
        'notes': _buildNotes(quote, notes),
        'created_at': now,
      });
      await txn.insert('document_lines', {
        'document_id': docId,
        'description': 'تأجير ${equipment.first['name']} '
            '(${equipment.first['code']}) لمدة $quantity ${period.label}',
        'quantity': quantity.toDouble(),
        'unit_price': agreedRate,
        'vat_rate': vatRate,
        'line_net': net,
        'line_vat': vat,
        'line_total': gross,
      });
      await txn.insert('rental_quotes', {
        'document_id': docId,
        'equipment_id': equipmentId,
        'customer_id': customerId,
        'employee_id': employeeId,
        'start_at': quote.start.toIso8601String(),
        'due_at': quote.due.toIso8601String(),
        'billing_unit': period.code,
        'billing_quantity': quantity,
        'billing_rate': agreedRate,
        'status': 'open',
        'created_at': now,
      });
      return docId;
    });
  }

  Future<int> createRental({
    required int equipmentId,
    required int customerId,
    int? employeeId,
    required DateTime start,
    required RentalPeriod period,
    required int quantity,
    required double agreedRate,
    required bool taxInvoice,
    String? notes,
  }) async {
    final db = await SindarDatabase.instance.database;
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final quote = RentalQuote.create(
      period: period, quantity: quantity, unitRate: agreedRate, start: start);
    final taxAllowed = policy.taxModeEnabled;
    final vatRate = taxInvoice && taxAllowed ? .15 : 0.0;
    final net = quote.total;
    final vat = double.parse((net * vatRate).toStringAsFixed(2));
    final gross = net + vat;

    return db.transaction((txn) async {
      final equipment = await txn.query('rental_equipment',
        where: 'id=? AND status=?',
        whereArgs: [equipmentId, 'available'], limit: 1);
      if (equipment.isEmpty) {
        throw const FormatException('المعدة غير متاحة للتأجير');
      }
      final customer = await txn.query('parties',
        where: "id=? AND type='customer'", whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw const FormatException('العميل غير موجود');
      await _validateEmployee(txn, employeeId);
      final active = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT COUNT(*) FROM equipment_rentals "
        "WHERE equipment_id=? AND status='active'", [equipmentId])) ?? 0;
      if (active > 0) throw const FormatException('هذه المعدة مؤجرة بالفعل');

      final sequence = await _nextSequence(txn, 'equipment_rental');
      final number = 'RNT-${sequence.toString().padLeft(6, '0')}';
      final now = DateTime.now().toUtc().toIso8601String();
      final docId = await txn.insert('documents', {
        'type': 'equipment_rental',
        'number': number,
        'date': now,
                'party_id': customerId,
        'party_name': customer.first['name'],
        'party_vat_number':
            taxAllowed ? customer.first['vat_number'] : null,
        'party_commercial_registration':
            taxAllowed ? customer.first['commercial_registration'] : null,
        'payment_method': 'credit',
        'status': 'approved',
        'subtotal': net,
        'vat_total': vat,
        'total': gross,
        'paid_amount': 0,
        'currency_code': policy.currencyCode,
        'notes': _buildNotes(quote, notes),
        'created_at': now,
      });
      await txn.insert('document_lines', {
        'document_id': docId,
        'description': 'تأجير ${equipment.first['name']} '
            '(${equipment.first['code']}) لمدة $quantity ${period.label}',
        'quantity': quantity.toDouble(),
        'unit_price': agreedRate,
        'vat_rate': vatRate,
        'line_net': net,
        'line_vat': vat,
        'line_total': gross,
      });
      await txn.insert('equipment_rentals', {
        'equipment_id': equipmentId,
        'customer_id': customerId,
        'employee_id': employeeId,
        'document_id': docId,
        'start_at': quote.start.toIso8601String(),
        'due_at': quote.due.toIso8601String(),
        'billing_unit': period.code,
        'billing_quantity': quantity,
        'billing_rate': agreedRate,
        'earned_amount': 0,
        'status': 'active',
        'created_at': now,
      });
      await txn.update('rental_equipment', {'status': 'rented'},
        where: 'id=?', whereArgs: [equipmentId]);
      await txn.insert('party_movements', {
        'party_id': customerId,
        'date': now,
        'reference': number,
        'operation_type': 'تأجير',
        'debit': gross,
        'credit': 0,
        'document_id': docId,
      });

      final entry = await txn.insert('journal_entries', {
        'date': now,
        'reference_type': 'equipment_rental',
        'reference_id': docId,
        'description': 'إثبات عقد التأجير $number',
        'created_at': now,
      });
      await txn.insert('journal_lines', {
        'entry_id': entry, 'account_code': '1103',
        'debit': gross, 'credit': 0,
      });
      await txn.insert('journal_lines', {
        'entry_id': entry, 'account_code': '2106',
        'debit': 0, 'credit': net,
      });
      if (vat > 0) {
        await txn.insert('journal_lines', {
          'entry_id': entry, 'account_code': '2102',
          'debit': 0, 'credit': vat,
        });
      }
      return docId;
    });
  }

  Future<int> convertQuote(int quoteDocumentId) async {
    final db = await SindarDatabase.instance.database;
    final found = await db.rawQuery(
      'SELECT q.*, d.vat_total, d.notes FROM rental_quotes q '
      'JOIN documents d ON d.id=q.document_id '
      "WHERE q.document_id=? AND q.status='open' LIMIT 1",
      [quoteDocumentId],
    );
    if (found.isEmpty) {
      throw const FormatException('عرض السعر غير متاح للتحويل');
    }
    final row = found.first;
    final period = RentalPeriod.values.firstWhere(
      (value) => value.code == row['billing_unit'],
      orElse: () => RentalPeriod.day,
    );
    final contractId = await createRental(
      equipmentId: row['equipment_id'] as int,
      customerId: row['customer_id'] as int,
      employeeId: row['employee_id'] as int?,
      start: DateTime.parse(row['start_at'] as String),
      period: period,
      quantity: row['billing_quantity'] as int,
      agreedRate: (row['billing_rate'] as num).toDouble(),
      taxInvoice: (row['vat_total'] as num).toDouble() > 0,
      notes: row['notes'] as String?,
    );
    await db.transaction((txn) async {
      await txn.update('rental_quotes', {
        'status': 'converted',
        'converted_document_id': contractId,
      }, where: 'document_id=?', whereArgs: [quoteDocumentId]);
      await txn.update('documents', {
        'status': 'converted',
        'linked_document_id': contractId,
      }, where: 'id=?', whereArgs: [quoteDocumentId]);
    });
    return contractId;
  }

  Future<int> addExpense({
    required int rentalId,
    int? employeeId,
    required String description,
    required double amount,
    String expenseAccount = '5204',
    String settlementAccount = '1101',
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw const FormatException('قيمة المصروف يجب أن تكون أكبر من صفر');
    }
    if (!const {'1101', '1102'}.contains(settlementAccount)) {
      throw const FormatException('اختر الصندوق أو البنك لحساب الصرف');
    }
    if (!const {'5204', '5207', '5102'}.contains(expenseAccount)) {
      throw const FormatException('حساب المصروف غير مسموح لهذه العملية');
    }
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final rental = await txn.rawQuery(
        'SELECT r.*, d.number AS rental_number FROM equipment_rentals r '
        'JOIN documents d ON d.id=r.document_id WHERE r.id=? LIMIT 1',
        [rentalId],
      );
      if (rental.isEmpty) throw const FormatException('عقد التأجير غير موجود');
      await _validateEmployee(txn, employeeId);
      final sequence = await _nextSequence(txn, 'payment_voucher');
      final number = 'PAY-${sequence.toString().padLeft(6, '0')}';
      final now = DateTime.now().toUtc().toIso8601String();
      final documentId = await txn.insert('documents', {
        'type': 'payment_voucher',
        'number': number,
        'date': now,
        'payment_method': settlementAccount == '1102' ? 'bank' : 'cash',
        'status': 'approved',
        'subtotal': amount,
        'vat_total': 0,
        'total': amount,
        'paid_amount': amount,
        'currency_code': policy.currencyCode,
        'linked_document_id': rental.first['document_id'],
        'notes': '${description.trim()} | عقد ${rental.first['rental_number']}',
        'created_at': now,
      });
      final entry = await txn.insert('journal_entries', {
        'date': now,
        'reference_type': 'rental_expense',
        'reference_id': documentId,
        'description': 'مصروف تأجير: ${description.trim()}',
        'created_at': now,
      });
      await txn.insert('journal_lines', {
        'entry_id': entry, 'account_code': expenseAccount,
        'debit': amount, 'credit': 0,
      });
      await txn.insert('journal_lines', {
        'entry_id': entry, 'account_code': settlementAccount,
        'debit': 0, 'credit': amount,
      });
      await txn.insert('rental_expenses', {
        'rental_id': rentalId,
        'document_id': documentId,
        'employee_id': employeeId,
        'description': description.trim(),
        'amount': amount,
        'expense_account': expenseAccount,
        'settlement_account': settlementAccount,
        'created_at': now,
      });
      return documentId;
    });
  }

  Future<void> markReturned(int rentalId) async {
    final db = await SindarDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('equipment_rentals',
        where: "id=? AND status='active'", whereArgs: [rentalId], limit: 1);
      if (rows.isEmpty) {
        throw const FormatException('العقد مغلق بالفعل أو غير موجود');
      }
      final equipmentId = rows.first['equipment_id'] as int;
      final updated = await txn.update('rental_equipment',
        {'status': 'available'},
        where: "id=? AND status='rented'", whereArgs: [equipmentId]);
      if (updated != 1) {
        throw const FormatException('حالة المعدة لا تسمح بإرجاعها');
      }
      await txn.update('equipment_rentals', {
        'status': 'returned',
        'returned_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id=?', whereArgs: [rentalId]);
    });
  }

  static Future<void> _validateEmployee(
    DatabaseExecutor db, int? employeeId) async {
    if (employeeId == null) return;
    final employee = await db.query('employees',
      columns: ['id'], where: 'id=? AND active=1',
      whereArgs: [employeeId], limit: 1);
    if (employee.isEmpty) {
      throw const FormatException('الموظف المختار غير نشط أو غير موجود');
    }
  }

  static String _buildNotes(RentalQuote quote, String? notes) {
    final base = 'من ${quote.start.toIso8601String()} '
        'إلى ${quote.due.toIso8601String()}';
    final extra = notes?.trim();
    return extra == null || extra.isEmpty ? base : '$base | $extra';
  }

  static Future<int> _nextSequence(
    DatabaseExecutor txn, String type) async {
    final rows = await txn.query('document_sequences',
      columns: ['next_number'], where: 'document_type=?',
      whereArgs: [type], limit: 1);
    if (rows.isEmpty) {
      await txn.insert('document_sequences',
        {'document_type': type, 'next_number': 2});
      return 1;
    }
    final current = rows.first['next_number'] as int;
    await txn.update('document_sequences',
      {'next_number': current + 1},
      where: 'document_type=?', whereArgs: [type]);
    return current;
  }
}
