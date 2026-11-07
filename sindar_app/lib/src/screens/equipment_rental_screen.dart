import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../services/rental_pricing.dart';
import '../services/rental_accrual_service.dart';
import '../theme/app_theme.dart';

import '../data/local/sindar_database.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/session_controller.dart';
import 'saved_documents_screen.dart';

/// One individually identifiable piece of equipment may be rented or sold.
class EquipmentRentalService {
  const EquipmentRentalService();

  Future<List<Map<String, Object?>>> equipment() async {
    final db = await SindarDatabase.instance.database;
    return db.query('rental_equipment', orderBy: 'name, code');
  }

  Future<List<Map<String, Object?>>> rentals() async {
    final db = await SindarDatabase.instance.database;
    return db.rawQuery(
      'SELECT r.*,d.number,d.total,d.paid_amount,p.name AS customer_name, '
      'e.name AS equipment_name,e.code AS equipment_code '
      'FROM equipment_rentals r '
      'JOIN documents d ON d.id=r.document_id '
      'JOIN parties p ON p.id=r.customer_id '
      'JOIN rental_equipment e ON e.id=r.equipment_id '
      'ORDER BY r.created_at DESC',
    );
  }

  Future<int> addEquipment({
    required String code,
    required String name,
    String? serial,
    required double dailyRate,
    required double hourlyRate,
    required double weeklyRate,
    required double monthlyRate,
    required double yearlyRate,
    required double purchasePrice,
    required double salePrice,
    int? catalogItemId,
  }) async {
    if (code.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('اسم المعدة ورمزها مطلوبان');
    }
    if ([dailyRate, hourlyRate, weeklyRate, monthlyRate, yearlyRate,
          purchasePrice, salePrice].any((v) => !v.isFinite || v < 0)) {
      throw const FormatException('أسعار المعدات يجب أن تكون غير سالبة');
    }
    final db = await SindarDatabase.instance.database;
    return db.insert('rental_equipment', {
      'code': code.trim(),
      'name': name.trim(),
      'serial_number': serial?.trim(),
      'daily_rate': dailyRate,
      'hourly_rate': hourlyRate,
      'weekly_rate': weeklyRate,
      'monthly_rate': monthlyRate,
      'yearly_rate': yearlyRate,
      'purchase_price': purchasePrice,
      'catalog_item_id': catalogItemId,
      'sale_price': salePrice,
      'status': 'available',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> rent({
    required int equipmentId,
    required int customerId,
    required DateTime start,
    required RentalPeriod period,
    required int quantity,
  }) async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final equipment = await txn.query('rental_equipment',
          where: 'id=? AND status=?', whereArgs: [equipmentId, 'available'], limit: 1);
      if (equipment.isEmpty) throw const FormatException('المعدة غير متاحة للتأجير');
      final customer = await txn.query('parties',
          where: "id=? AND type='customer'", whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw const FormatException('العميل غير موجود');
      final active = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT COUNT(*) FROM equipment_rentals WHERE equipment_id=? AND status='active'",
        [equipmentId],
      )) ?? 0;
      if (active > 0) throw const FormatException('هذه المعدة مؤجرة بالفعل');
      final field = switch (period) {
        RentalPeriod.hour => 'hourly_rate',
        RentalPeriod.day => 'daily_rate',
        RentalPeriod.week => 'weekly_rate',
        RentalPeriod.month => 'monthly_rate',
        RentalPeriod.year => 'yearly_rate',
      };
      final rate = (equipment.first[field] as num).toDouble();
      final quote = RentalQuote.create(
        period: period, quantity: quantity, unitRate: rate, start: start);
      final total = quote.total;
      final seq = await _nextSequence(txn, 'equipment_rental');
      final number = 'RNT-${seq.toString().padLeft(6, '0')}';
      final now = DateTime.now().toUtc().toIso8601String();
      final docId = await txn.insert('documents', {
        'type': 'equipment_rental',
        'number': number,
        'date': now,
        'party_id': customerId,
        'party_name': customer.first['name'],
        'payment_method': 'credit',
        'status': 'approved',
        'subtotal': total,
        'vat_total': 0,
        'total': total,
        'paid_amount': 0,
        'currency_code': policy.currencyCode,
        'notes': 'من ${quote.start.toIso8601String()} '
            'إلى ${quote.due.toIso8601String()} | $quantity ${period.label}',
        'created_at': now,
      });
      await txn.insert('document_lines', {
        'document_id': docId,
        'description': 'تأجير ${equipment.first['name']} (${equipment.first['code']})'
            ' لمدة $quantity ${period.label}',
        'quantity': quantity.toDouble(),
        'unit_price': rate,
        'vat_rate': 0,
        'line_net': total,
        'line_vat': 0,
        'line_total': total,
      });
      await txn.insert('equipment_rentals', {
        'equipment_id': equipmentId,
        'customer_id': customerId,
        'document_id': docId,
        'start_at': quote.start.toIso8601String(),
        'due_at': quote.due.toIso8601String(),
        'billing_unit': period.code,
        'billing_quantity': quantity,
        'billing_rate': rate,
        'earned_amount': 0,
        'status': 'active',
        'created_at': now,
      });
      await txn.update('rental_equipment', {'status': 'rented'},
          where: 'id=?', whereArgs: [equipmentId]);
      await txn.insert('party_movements', {
        'party_id': customerId, 'date': now, 'reference': number,
        'operation_type': 'إيجار معدات', 'debit': total,
        'credit': 0, 'document_id': docId,
      });
      // Contract invoiced now; recognize rent only as the time elapses.
      await _journal(txn, referenceType: 'equipment_rental',
        referenceId: docId, description: 'فاتورة عقد تأجير $number',
        debitAccount: '1103', creditAccount: '2106', amount: total);
      return docId;
    });
  }

  Future<void> markReturned(int rentalId) async {
    final db = await SindarDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('equipment_rentals',
          where: "id=? AND status='active'", whereArgs: [rentalId], limit: 1);
      if (rows.isEmpty) throw const FormatException('العقد مغلق بالفعل أو غير موجود');
      final equipmentId = rows.first['equipment_id'] as int;
      final updated = await txn.update('rental_equipment', {'status': 'available'},
          where: "id=? AND status='rented'", whereArgs: [equipmentId]);
      if (updated != 1) throw const FormatException('حالة المعدة لا تسمح بإرجاعها');
      await txn.update('equipment_rentals', {
        'status': 'returned',
        'returned_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id=?', whereArgs: [rentalId]);
    });
  }

  Future<int> sell({required int equipmentId, required int customerId}) async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final equipment = await txn.query('rental_equipment',
          where: "id=? AND status='available'", whereArgs: [equipmentId], limit: 1);
      if (equipment.isEmpty) throw const FormatException('المعدة ليست متاحة للبيع');
      final customer = await txn.query('parties',
          where: "id=? AND type='customer'", whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw const FormatException('اختر عميلاً مسجلاً');
      final price = (equipment.first['sale_price'] as num).toDouble();
      if (price <= 0) throw const FormatException('حدد سعر بيع المعدة');
      final seq = await _nextSequence(txn, 'sales_invoice');
      final number = 'INV-${seq.toString().padLeft(6, '0')}';
      final now = DateTime.now().toUtc().toIso8601String();
      final docId = await txn.insert('documents', {
        'type': 'sales_invoice', 'number': number,
        'date': now, 'party_id': customerId, 'party_name': customer.first['name'],
        'payment_method': 'credit', 'status': 'approved',
        'subtotal': price, 'vat_total': 0, 'total': price,
        'paid_amount': 0, 'currency_code': policy.currencyCode,
        'notes': 'بيع معدة ${equipment.first['code']}',
        'created_at': now,
      });
      await txn.insert('document_lines', {
        'document_id': docId,
        'description': 'بيع ${equipment.first['name']} - ${equipment.first['code']}',
        'quantity': 1, 'unit_price': price, 'vat_rate': 0,
        'line_net': price, 'line_vat': 0, 'line_total': price,
      });
      await txn.update('rental_equipment', {'status': 'sold'},
          where: 'id=?', whereArgs: [equipmentId]);
      await txn.insert('party_movements', {
        'party_id': customerId, 'date': now,
        'reference': number, 'operation_type': 'بيع معدات',
        'debit': price, 'credit': 0, 'document_id': docId,
      });
      await _journal(txn, referenceType: 'sales_invoice', referenceId: docId,
        description: 'بيع معدة $number', debitAccount: '1103',
        creditAccount: '4101', amount: price);
      return docId;
    });
  }

  static Future<int> _nextSequence(Transaction txn, String type) async {
    final rows = await txn.query('document_sequences',
      columns: ['next_number'], where: 'document_type=?',
      whereArgs: [type], limit: 1);
    if (rows.isEmpty) {
      await txn.insert('document_sequences', {'document_type': type, 'next_number': 2});
      return 1;
    }
    final next = rows.first['next_number'] as int;
    await txn.update('document_sequences', {'next_number': next + 1},
      where: 'document_type=?', whereArgs: [type]);
    return next;
  }

  static Future<void> _journal(Transaction txn, {
    required String referenceType,
    required int referenceId,
    required String description,
    required String debitAccount,
    required String creditAccount,
    required double amount,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await txn.insert('journal_entries', {
      'date': now, 'reference_type': referenceType,
      'reference_id': referenceId, 'description': description,
      'created_at': now,
    });
    await txn.insert('journal_lines', {
      'entry_id': id, 'account_code': debitAccount, 'debit': amount, 'credit': 0,
    });
    await txn.insert('journal_lines', {
      'entry_id': id, 'account_code': creditAccount, 'debit': 0, 'credit': amount,
    });
  }
}

class EquipmentRentalScreen extends StatefulWidget {
  const EquipmentRentalScreen({super.key});
  @override
  State<EquipmentRentalScreen> createState() => _EquipmentRentalScreenState();
}

class _EquipmentRentalScreenState extends State<EquipmentRentalScreen> {
  final _service = const EquipmentRentalService();
  List<Map<String, Object?>> _equipment = const [];
  List<Map<String, Object?>> _rentals = const [];
  List<PartyRecord> _customers = const [];
  bool _busy = true;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final equipment = await _service.equipment();
    final rentals = await _service.rentals();
    final customers = await ErpRepository.instance.listParties('customer');
    if (!mounted) return;
    setState(() { _equipment = equipment; _rentals = rentals; _customers = customers; _busy = false; });
  }

  Future<bool> _authorize(String action) async {
    final allowed = await SessionController.instance.can('assets', action: action);
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية تنفيذ العملية')),
      );
    }
    return allowed;
  }

  Future<void> _add() async {
    if (!await _authorize('add')) return;
    if (!mounted) return;
    final code = TextEditingController();
    final name = TextEditingController();
    final serial = TextEditingController();
    final daily = TextEditingController(text: '0');
    final sale = TextEditingController(text: '0');
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) =>
        AlertDialog(title: const Text('إضافة معدة'), content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز المعدة')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المعدة')),
            TextField(controller: serial, decoration: const InputDecoration(labelText: 'الرقم التسلسلي')),
            TextField(controller: daily, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إيجار اليوم')),
            TextField(controller: sale, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ]));
      if (accepted != true) return;
      await _service.addEquipment(code: code.text, name: name.text,
        serial: serial.text, dailyRate: double.parse(daily.text),
        salePrice: double.parse(sale.text));
      await _refresh();
    } catch (error) { _error(error); }
    finally { code.dispose(); name.dispose(); serial.dispose(); daily.dispose(); sale.dispose(); }
  }

  Future<void> _operate(Map<String, Object?> equipment, {required bool sale}) async {
    if (!await _authorize('approve')) return;
    if (!mounted) return;
    if (_customers.isEmpty) {
      _error('أضف عميلاً أولاً من قسم العملاء');
      return;
    }
    int? customerId;
    DateTime start = DateTime.now();
    DateTime due = DateTime.now();
    final action = await showDialog<bool>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(sale ? 'بيع ${equipment['name']}' : 'تأجير ${equipment['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            isExpanded: true, decoration: const InputDecoration(labelText: 'العميل'),
            items: [for (final customer in _customers)
              DropdownMenuItem(value: customer.id, child: Text(customer.name))],
            onChanged: (value) => update(() => customerId = value)),
          if (!sale) ...[
            ListTile(title: const Text('بداية التأجير'), subtitle: Text('${start.year}-${start.month}-${start.day}'),
              onTap: () async { final date = await showDatePicker(context: context,
                initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (date != null) update(() => start = date); }),
            ListTile(title: const Text('موعد الإرجاع'), subtitle: Text('${due.year}-${due.month}-${due.day}'),
              onTap: () async { final date = await showDatePicker(context: context,
                initialDate: due, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (date != null) update(() => due = date); }),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: customerId == null ? null : () => Navigator.pop(context, true),
            child: Text(sale ? 'اعتماد البيع الآجل' : 'حفظ عقد التأجير')),
        ],
      )));
    if (action != true || customerId == null) return;
    try {
      final id = sale
          ? await _service.sell(equipmentId: equipment['id'] as int, customerId: customerId!)
          : await _service.rent(equipmentId: equipment['id'] as int,
              customerId: customerId!, start: start, due: due);
      await _refresh();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
    } catch (error) { _error(error); }
  }

  Future<void> _returnEquipment(Map<String, Object?> rental) async {
    if (!await _authorize('edit')) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('تأكيد استرجاع المعدة'),
      content: Text('هل تم استلام ${rental['equipment_name']} من العميل فعلاً؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تم الاستلام')),
      ],
    ));
    if (confirmed != true) return;
    try { await _service.markReturned(rental['id'] as int); await _refresh(); }
    catch (error) { _error(error); }
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: const Text('بيع وتأجير المعدات'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add, icon: const Icon(Icons.add), label: const Text('إضافة معدة')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              Text('المعدات (${_equipment.length})', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_equipment.isEmpty) const Card(child: ListTile(title: Text('لا توجد معدات بعد'))),
              for (final equipment in _equipment)
                Card(child: ListTile(
                  leading: const Icon(Icons.handyman_outlined),
                  title: Text('${equipment['name']} • ${equipment['code']}'),
                  subtitle: Text('الحالة: ${switch (equipment['status']) {
                    'available' => 'متاحة', 'rented' => 'مؤجرة', 'maintenance' => 'صيانة',
                    'sold' => 'مباعة', _ => equipment['status'],
                  }} | يومي: ${equipment['daily_rate']} | بيع: ${equipment['sale_price']}'),
                  trailing: equipment['status'] == 'available'
                      ? Wrap(spacing: 4, children: [
                          OutlinedButton(onPressed: () => _operate(equipment, sale: false),
                            child: const Text('تأجير')),
                          FilledButton.tonal(onPressed: () => _operate(equipment, sale: true),
                            child: const Text('بيع')),
                        ])
                      : null,
                )),
              const SizedBox(height: 22),
              Text('عقود التأجير (${_rentals.length})', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_rentals.isEmpty) const Card(child: ListTile(title: Text('لا توجد عقود بعد'))),
              for (final rental in _rentals)
                Card(child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('${rental['number']} • ${rental['equipment_name']}'),
                  subtitle: Text('${rental['customer_name']} | ${rental['total']} | '
                    '${rental['status'] == 'returned' ? 'تم الإرجاع' :
                      DateTime.parse(rental['due_at'] as String).isBefore(now) ? 'متأخرة' : 'مؤجرة'}'),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => SavedDocumentPreviewScreen(documentId: rental['document_id'] as int))),
                  trailing: rental['status'] == 'active'
                      ? TextButton(onPressed: () => _returnEquipment(rental), child: const Text('استرجاع'))
                      : const Icon(Icons.check_circle_outline),
                )),
              const SizedBox(height: 90),
            ]),
    );
  }
}
