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
  List<ItemRecord> _catalog = const [];
  bool _busy = true;

  static const _black = Color(0xFF111318);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await const RentalAccrualService().accrue();
      final equipment = await _service.equipment();
      final rentals = await _service.rentals();
      final customers = await ErpRepository.instance.listParties('customer');
      final items = await ErpRepository.instance.listItems();
      if (!mounted) return;
      setState(() {
        _equipment = equipment;
        _rentals = rentals;
        _customers = customers;
        _catalog = items;
        _busy = false;
      });
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _error(error);
    }
  }

  Future<bool> _authorize(String action) async {
    final allowed = await SessionController.instance.can('assets', action: action);
    if (!allowed && mounted) {
      _error('ليس لديك صلاحية تنفيذ العملية');
    }
    return allowed;
  }

  static double _rate(Map<String, Object?> equipment, RentalPeriod period) {
    final field = switch (period) {
      RentalPeriod.hour => 'hourly_rate',
      RentalPeriod.day => 'daily_rate',
      RentalPeriod.week => 'weekly_rate',
      RentalPeriod.month => 'monthly_rate',
      RentalPeriod.year => 'yearly_rate',
    };
    return (equipment[field] as num?)?.toDouble() ?? 0;
  }

  static String _money(Object? value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  static String _dateTime(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    if (!await _authorize('add') || !mounted) return;
    final code = TextEditingController();
    final name = TextEditingController();
    final serial = TextEditingController();
    final purchase = TextEditingController(text: '0');
    final sale = TextEditingController(text: '0');
    final hourly = TextEditingController(text: '0');
    final daily = TextEditingController(text: '0');
    final weekly = TextEditingController(text: '0');
    final monthly = TextEditingController(text: '0');
    final yearly = TextEditingController(text: '0');
    final all = [code, name, serial, purchase, sale, hourly, daily, weekly,
      monthly, yearly];
    int? catalogItemId;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: const Text('تسجيل معدة للتأجير'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_catalog.isNotEmpty)
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: catalogItemId,
                      decoration: const InputDecoration(
                        labelText: 'ربط بصنف موجود (مرجعي واختياري)',
                      ),
                      items: [for (final item in _catalog)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text('${item.name} | شراء ${item.purchasePrice} | بيع ${item.salePrice}',
                            overflow: TextOverflow.ellipsis),
                        )],
                      onChanged: (id) {
                        final item = _catalog.where((e) => e.id == id).firstOrNull;
                        update(() {
                          catalogItemId = id;
                          if (item != null) {
                            code.text = item.code;
                            name.text = item.name;
                            purchase.text = item.purchasePrice.toStringAsFixed(2);
                            sale.text = item.salePrice.toStringAsFixed(2);
                          }
                        });
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('ربط الصنف يستورد الاسم وسعر الشراء والبيع فقط. '
                        'لا يخصم من المخزون ولا يثبت شراء أصل محاسبياً.',
                      style: TextStyle(fontSize: 12)),
                  ),
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز المعدة')),
                  const SizedBox(height: 8),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المعدة')),
                  const SizedBox(height: 8),
                  TextField(controller: serial, decoration: const InputDecoration(labelText: 'الرقم التسلسلي')),
                  const SizedBox(height: 8),
                  TextField(controller: purchase, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'تكلفة الشراء (مرجعية)')),
                  const SizedBox(height: 8),
                  TextField(controller: sale, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر البيع (مرجعي)')),
                  const SizedBox(height: 8),
                  TextField(controller: hourly, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'إيجار الساعة')),
                  const SizedBox(height: 8),
                  TextField(controller: daily, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'إيجار اليوم')),
                  const SizedBox(height: 8),
                  TextField(controller: weekly, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'إيجار الأسبوع')),
                  const SizedBox(height: 8),
                  TextField(controller: monthly, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'إيجار الشهر')),
                  const SizedBox(height: 8),
                  TextField(controller: yearly, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'إيجار السنة')),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ')),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      double value(TextEditingController c) {
        final parsed = double.tryParse(c.text.trim());
        if (parsed == null) throw const FormatException('تأكد من كتابة الأسعار بالأرقام الصحيحة');
        return parsed;
      }
      await _service.addEquipment(
        code: code.text, name: name.text, serial: serial.text,
        purchasePrice: value(purchase), salePrice: value(sale),
        hourlyRate: value(hourly), dailyRate: value(daily),
        weeklyRate: value(weekly), monthlyRate: value(monthly),
        yearlyRate: value(yearly), catalogItemId: catalogItemId,
      );
      await _refresh();
    } catch (error) {
      _error(error);
    } finally {
      for (final c in all) { c.dispose(); }
    }
  }

  Future<void> _rentEquipment(Map<String, Object?> equipment) async {
    if (!await _authorize('approve') || !mounted) return;
    if (_customers.isEmpty) {
      _error('أضف عميلاً أولاً من قسم العملاء');
      return;
    }
    int? customerId;
    DateTime start = DateTime.now();
    RentalPeriod period = RentalPeriod.day;
    final quantity = TextEditingController(text: '1');
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) {
            final count = int.tryParse(quantity.text.trim());
            RentalQuote? quote;
            try {
              if (count != null) {
                quote = RentalQuote.create(
                  period: period, quantity: count,
                  unitRate: _rate(equipment, period), start: start);
              }
            } on FormatException { /* Invalid period, show validation below. */ }
            return AlertDialog(
              title: Text('عقد تأجير • ${equipment['name']}'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: customerId,
                      decoration: const InputDecoration(labelText: 'اسم العميل'),
                      items: [for (final c in _customers)
                        DropdownMenuItem(value: c.id, child: Text(c.name))],
                      onChanged: (v) => update(() => customerId = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<RentalPeriod>(
                      initialValue: period,
                      decoration: const InputDecoration(labelText: 'وحدة التأجير'),
                      items: [for (final unit in RentalPeriod.values)
                        DropdownMenuItem(value: unit, child: Text('بال${unit.label}'))],
                      onChanged: (v) { if (v != null) update(() => period = v); },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'عدد الساعات / الأيام / المدد'),
                      onChanged: (_) => update(() {}),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('بداية التأجير'),
                      subtitle: Text(_dateTime(start)),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: dialogContext, initialDate: start,
                          firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (date == null || !dialogContext.mounted) return;
                        final time = await showTimePicker(
                          context: dialogContext, initialTime: TimeOfDay.fromDateTime(start));
                        if (time == null) return;
                        update(() => start = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute));
                      },
                    ),
                    const SizedBox(height: 8),
                    if (quote == null)
                      const Text('حدد سعر الوحدة ومدتها أولاً',
                        style: TextStyle(color: Colors.red))
                    else
                      Card(child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('سعر الوحدة: ${quote.unitRate.toStringAsFixed(2)}'),
                          Text('موعد الإرجاع: ${_dateTime(quote.due.toLocal())}'),
                          Text('إجمالي العقد: ${quote.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                      )),
                  ]),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء')),
                FilledButton(
                  onPressed: customerId == null || quote == null
                      ? null : () => Navigator.pop(dialogContext, true),
                  child: const Text('اعتماد عقد التأجير'),
                ),
              ],
            );
          },
        ),
      );
      if (accepted != true || customerId == null) return;
      final id = await _service.rent(
        equipmentId: equipment['id'] as int, customerId: customerId!,
        start: start, period: period, quantity: int.parse(quantity.text.trim()),
      );
      await _refresh();
      if (mounted) {
        await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
      }
    } catch (error) {
      _error(error);
    } finally {
      quantity.dispose();
    }
  }

  Future<void> _receipt(Map<String, Object?> rental) async {
    if (!await _authorize('approve') || !mounted) return;
    final outstanding = (rental['total'] as num).toDouble() -
        (rental['paid_amount'] as num).toDouble();
    if (outstanding <= 0.005) return;
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    String settlement = '1101';
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text('سند قبض • ${rental['number']}'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('العميل: ${rental['customer_name']}'),
              Text('المتبقي: ${outstanding.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ المقبوض')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: settlement,
                decoration: const InputDecoration(labelText: 'حساب القبض'),
                items: const [
                  DropdownMenuItem(value: '1101', child: Text('الصندوق - نقداً')),
                  DropdownMenuItem(value: '1102', child: Text('الحساب البنكي')),
                ],
                onChanged: (v) { if (v != null) update(() => settlement = v); },
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ سند القبض')),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      final number = double.tryParse(amount.text.trim());
      if (number == null || number <= 0 || number > outstanding + 0.005) {
        throw const FormatException('قيمة القبض غير صحيحة أو تتجاوز المتبقي');
      }
      final id = await ErpRepository.instance.createVoucher(
        receipt: true, amount: number,
        partyId: rental['customer_id'] as int,
        partyName: rental['customer_name'] as String?,
        linkedDocumentId: rental['document_id'] as int,
        settlementAccountCode: settlement,
        notes: 'قبض إيجار عن العقد ${rental['number']}',
      );
      await _refresh();
      if (mounted) {
        await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
      }
    } catch (error) {
      _error(error);
    } finally {
      amount.dispose();
    }
  }

  Future<void> _returnEquipment(Map<String, Object?> rental) async {
    if (!await _authorize('edit') || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد استلام المعدة'),
        content: const Text(
          'سيتم تحرير المعدة لتأجير جديد. الإرجاع المبكر لا يلغي '
          'المبلغ المستحق ولا ينشئ استرداداً تلقائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد الاستلام')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service.markReturned(rental['id'] as int);
      await _refresh();
    } catch (error) { _error(error); }
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final available = _equipment.where((e) => e['status'] == 'available').length;
    final active = _rentals.where((r) => r['status'] == 'active').length;
    final outstanding = _rentals.fold<double>(0, (sum, r) =>
      sum + (r['total'] as num).toDouble() - (r['paid_amount'] as num).toDouble());
    final outer = Theme.of(context);
    final theme = outer.copyWith(
      colorScheme: outer.colorScheme.copyWith(
        primary: _black, secondary: AppColors.gold),
      appBarTheme: const AppBarTheme(
        backgroundColor: _black, foregroundColor: AppColors.gold),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold, foregroundColor: _black),
    );
    return Theme(data: theme, child: Scaffold(
      appBar: AppBar(title: const Text('سِندار | قسم تأجير المعدات'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add, icon: const Icon(Icons.add),
        label: const Text('إضافة معدة')),
      body: _busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(14), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: _black,
                borderRadius: BorderRadius.circular(22)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.construction_rounded, size: 36, color: AppColors.gold),
                  SizedBox(height: 8),
                  Text('إدارة المعدات والتأجير',
                    style: TextStyle(color: AppColors.gold, fontSize: 22,
                      fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('هوية مستقلة • عقود بالمدة • قبض مرتبط • حسابات تأجير منفصلة',
                    style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(avatar: const Icon(Icons.handyman, size: 18),
                label: Text('المعدات ${_equipment.length}')),
              Chip(avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('المتاحة $available')),
              Chip(avatar: const Icon(Icons.schedule, size: 18),
                label: Text('العقود النشطة $active')),
              Chip(avatar: const Icon(Icons.payments_outlined, size: 18),
                label: Text('المتبقي ${outstanding.toStringAsFixed(2)}')),
            ]),
            const SizedBox(height: 15),
            Text('سجل المعدات', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_equipment.isEmpty)
              const Card(child: ListTile(title: Text('لم تتم إضافة معدات بعد'))),
            for (final equipment in _equipment)
              Card(child: Padding(
                padding: const EdgeInsets.all(7),
                child: Column(children: [
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: AppColors.gold,
                      child: Icon(Icons.handyman, color: _black)),
                    title: Text('${equipment['name']} | ${equipment['code']}'),
                    subtitle: Text('الحالة: ${switch (equipment['status']) {
                      'available' => 'متاحة', 'rented' => 'مؤجرة',
                      'maintenance' => 'صيانة', 'sold' => 'مباعة',
                      _ => equipment['status'],
                    }} | تكلفة: ${_money(equipment['purchase_price'])} | '
                    'بيع مرجعي: ${_money(equipment['sale_price'])}'),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ساعة ${_money(equipment['hourly_rate'])} | '
                      'يوم ${_money(equipment['daily_rate'])} | '
                      'أسبوع ${_money(equipment['weekly_rate'])} | '
                      'شهر ${_money(equipment['monthly_rate'])} | '
                      'سنة ${_money(equipment['yearly_rate'])}')),
                  if (equipment['status'] == 'available')
                    Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                      onPressed: () => _rentEquipment(equipment),
                      icon: const Icon(Icons.assignment_add),
                      label: const Text('تأجير هذه المعدة'),
                    )),
                ]),
              )),
            const SizedBox(height: 18),
            Text('عقود التأجير', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_rentals.isEmpty)
              const Card(child: ListTile(title: Text('لا توجد عقود محفوظة'))),
            for (final rental in _rentals)
              Card(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${rental['number']} • ${rental['equipment_name']}'),
                    subtitle: Text('${rental['customer_name']} | '
                      '${rental['billing_quantity']} × ${rental['billing_unit']} | '
                      'الإجمالي ${_money(rental['total'])}\n'
                      'مقبوض ${_money(rental['paid_amount'])} | '
                      '${rental['status'] == 'returned' ? 'تم الاستلام' :
                        DateTime.parse(rental['due_at'] as String).isBefore(now)
                        ? 'متأخرة' : 'مؤجرة'}'),
                    isThreeLine: true,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) =>
                        SavedDocumentPreviewScreen(
                          documentId: rental['document_id'] as int))),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(spacing: 8, children: [
                      if ((rental['total'] as num).toDouble() -
                            (rental['paid_amount'] as num).toDouble() > 0.005)
                        FilledButton.icon(
                          onPressed: () => _receipt(rental),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('سند قبض'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) =>
                            SavedDocumentPreviewScreen(
                              documentId: rental['document_id'] as int))),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('عرض العقد'),
                      ),
                      if (rental['status'] == 'active')
                        OutlinedButton(
                          onPressed: () => _returnEquipment(rental),
                          child: const Text('استلام المعدة'),
                        ),
                    ]),
                  ),
                ]),
              )),
            const SizedBox(height: 90),
          ]),
    ));
  }
}
