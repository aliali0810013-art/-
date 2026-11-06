import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sindar_core/sindar_core.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/sindar_database.dart';
import 'operational_models.dart';

class ErpRepository {
  ErpRepository._();

  static final ErpRepository instance = ErpRepository._();

  static const licenseSigningSecret = 'sindar-offline-signing-key-v1';

  Future<void> initialize() async {
    final db = await SindarDatabase.instance.database;
    final seeded = await SindarDatabase.instance.getSetting('demo_seeded_v2');
    if (seeded == 'true') return;

    await db.transaction((txn) async {
      final now = DateTime.utc(2026, 11, 7, 2).toIso8601String();

      const policy = LicensePolicy(
        customerId: 'DEMO-SINDAR',
        isTaxEnabled: true,
        countryCode: 'SA',
        currencyCode: 'SAR',
        currencySymbol: 'ر.س',
        maxUsers: 5,
      );
      await txn.insert(
        'app_settings',
        {
          'setting_key': 'license_policy',
          'setting_value': jsonEncode(policy.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final userCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          0;
      if (userCount == 0) {
        await txn.insert('users', {
          'name': 'مدير النظام',
          'role': 'admin',
          'login_code': 'admin',
          'pin_hash': _hashPin('1234'),
          'active': 1,
          'is_system_admin': 1,
          'created_at': now,
        });
      }

      final partyCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM parties'),
          ) ??
          0;
      int customerId;
      int supplierId;
      if (partyCount == 0) {
        customerId = await txn.insert('parties', {
          'type': 'customer',
          'name': 'شركة الواجهة الحديثة',
          'vat_number': '310123456700003',
          'commercial_registration': '1010101010',
          'phone': '0500000001',
          'credit_limit': 50000,
          'opening_balance': 0,
          'created_at': now,
        });
        supplierId = await txn.insert('parties', {
          'type': 'supplier',
          'name': 'مؤسسة التوريد الذهبي',
          'vat_number': '310987654300003',
          'commercial_registration': '1010102020',
          'phone': '0500000002',
          'credit_limit': 0,
          'opening_balance': 0,
          'created_at': now,
        });
      } else {
        final customer = await txn.query(
          'parties',
          where: 'type = ?',
          whereArgs: ['customer'],
          limit: 1,
        );
        final supplier = await txn.query(
          'parties',
          where: 'type = ?',
          whereArgs: ['supplier'],
          limit: 1,
        );
        customerId = customer.isNotEmpty ? customer.first['id']! as int : 0;
        supplierId = supplier.isNotEmpty ? supplier.first['id']! as int : 0;
      }

      final itemCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM items'),
          ) ??
          0;
      if (itemCount == 0) {
        await txn.insert('items', {
          'code': 'ITM-001',
          'barcode': '6281000000012',
          'name': 'صنف تجريبي رئيسي',
          'purchase_price': 50,
          'sale_price': 75,
          'quantity': 2500,
          'reorder_level': 100,
          'created_at': now,
        });
      }

      final documentCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM documents'),
          ) ??
          0;
      if (documentCount == 0) {
        final invoice1 = await _seedDocument(
          txn,
          type: 'sales_invoice',
          number: 'INV-000245',
          date: DateTime.utc(2026, 11, 7, 10),
          partyId: customerId == 0 ? null : customerId,
          partyName: 'شركة الواجهة الحديثة',
          partyVat: '310123456700003',
          subtotal: 10869.57,
          vat: 1630.43,
          total: 12500,
          currency: 'SAR',
          paymentMethod: 'credit',
        );
        await _seedDocument(
          txn,
          type: 'sales_invoice',
          number: 'INV-000244',
          date: DateTime.utc(2026, 11, 1, 11),
          partyId: customerId == 0 ? null : customerId,
          partyName: 'شركة الواجهة الحديثة',
          partyVat: '310123456700003',
          subtotal: 116521.73,
          vat: 17478.27,
          total: 134000,
          currency: 'SAR',
          paymentMethod: 'cash',
        );
        await _seedDocument(
          txn,
          type: 'quotation',
          number: 'QUO-000128',
          date: DateTime.utc(2026, 11, 7, 9),
          partyId: customerId == 0 ? null : customerId,
          partyName: 'شركة الواجهة الحديثة',
          subtotal: 6956.52,
          vat: 1043.48,
          total: 8000,
          currency: 'SAR',
          paymentMethod: 'cash',
        );
        final receiptId = await _seedDocument(
          txn,
          type: 'receipt_voucher',
          number: 'REC-000067',
          date: DateTime.utc(2026, 11, 6, 15),
          partyId: customerId == 0 ? null : customerId,
          partyName: 'شركة الواجهة الحديثة',
          subtotal: 5500,
          vat: 0,
          total: 5500,
          currency: 'SAR',
          paymentMethod: 'cash',
        );
        final purchase1 = await _seedDocument(
          txn,
          type: 'purchase_invoice',
          number: 'PUR-000097',
          date: DateTime.utc(2026, 11, 5, 13),
          partyId: supplierId == 0 ? null : supplierId,
          partyName: 'مؤسسة التوريد الذهبي',
          partyVat: '310987654300003',
          subtotal: 5913.04,
          vat: 886.96,
          total: 6800,
          currency: 'SAR',
          paymentMethod: 'credit',
        );
        await _seedDocument(
          txn,
          type: 'purchase_invoice',
          number: 'PUR-000096',
          date: DateTime.utc(2026, 11, 2, 12),
          partyId: supplierId == 0 ? null : supplierId,
          partyName: 'مؤسسة التوريد الذهبي',
          partyVat: '310987654300003',
          subtotal: 53869.57,
          vat: 8080.43,
          total: 61950,
          currency: 'SAR',
          paymentMethod: 'credit',
        );

        await _postJournalTxn(
          txn,
          AutomaticPosting.sales(
            date: DateTime.utc(2026, 11, 7),
            referenceId: invoice1,
            net: 127391.30,
            vat: 19108.70,
            onCredit: false,
          ),
        );
        await _postJournalTxn(
          txn,
          JournalDraft(
            date: DateTime.utc(2026, 11, 7),
            description: 'تكلفة البضاعة المباعة - بيانات تجريبية',
            referenceType: 'demo_cogs',
            referenceId: 1,
            lines: const [
              JournalLineDraft(accountCode: '5101', debit: 81621.30),
              JournalLineDraft(accountCode: '1104', credit: 81621.30),
            ],
          ),
        );
        await _postJournalTxn(
          txn,
          JournalDraft(
            date: DateTime.utc(2026, 11, 7),
            description: 'مصروفات تشغيلية - بيانات تجريبية',
            referenceType: 'demo_expense',
            referenceId: 1,
            lines: const [
              JournalLineDraft(accountCode: '5207', debit: 17320),
              JournalLineDraft(accountCode: '1101', credit: 17320),
            ],
          ),
        );
        await _postJournalTxn(
          txn,
          AutomaticPosting.receipt(
            date: DateTime.utc(2026, 11, 6),
            referenceId: receiptId,
            amount: 5500,
          ),
        );

        if (customerId != 0) {
          await txn.insert('party_movements', {
            'party_id': customerId,
            'date': DateTime.utc(2026, 11, 7, 10).toIso8601String(),
            'reference': 'INV-000245',
            'operation_type': 'فاتورة مبيعات',
            'debit': 12500,
            'credit': 0,
            'document_id': invoice1,
          });
          await txn.insert('party_movements', {
            'party_id': customerId,
            'date': DateTime.utc(2026, 11, 6, 15).toIso8601String(),
            'reference': 'REC-000067',
            'operation_type': 'سند قبض',
            'debit': 0,
            'credit': 5500,
            'document_id': receiptId,
          });
        }
        if (supplierId != 0) {
          await txn.insert('party_movements', {
            'party_id': supplierId,
            'date': DateTime.utc(2026, 11, 5, 13).toIso8601String(),
            'reference': 'PUR-000097',
            'operation_type': 'فاتورة مشتريات',
            'debit': 0,
            'credit': 6800,
            'document_id': purchase1,
          });
        }

        final sequenceValues = <String, int>{
          'sales_invoice': 246,
          'purchase_invoice': 98,
          'quotation': 129,
          'receipt_voucher': 68,
        };
        for (final entry in sequenceValues.entries) {
          await txn.update(
            'document_sequences',
            {'next_number': entry.value},
            where: 'document_type = ?',
            whereArgs: [entry.key],
          );
        }
      }

      await txn.insert(
        'app_settings',
        {'setting_key': 'demo_seeded_v2', 'setting_value': 'true'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static Future<int> _seedDocument(
    DatabaseExecutor txn, {
    required String type,
    required String number,
    required DateTime date,
    required String partyName,
    required double subtotal,
    required double vat,
    required double total,
    required String currency,
    required String paymentMethod,
    int? partyId,
    String? partyVat,
  }) async {
    return txn.insert('documents', {
      'type': type,
      'number': number,
      'date': date.toIso8601String(),
      'party_id': partyId,
      'party_name': partyName,
      'party_vat_number': partyVat,
      'payment_method': paymentMethod,
      'status': 'approved',
      'subtotal': subtotal,
      'vat_total': vat,
      'total': total,
      'paid_amount': paymentMethod == 'cash' ? total : 0,
      'currency_code': currency,
      'created_at': date.toIso8601String(),
    });
  }

  Future<DashboardSnapshot> dashboard({
    required int year,
    required int month,
  }) async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    final start = DateTime.utc(year, month);
    final end = month == 12
        ? DateTime.utc(year + 1, 1)
        : DateTime.utc(year, month + 1);

    Future<double> documentTotal(String type) async {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(total),0) AS value FROM documents '
        'WHERE type = ? AND date >= ? AND date < ? AND status != ?',
        [type, start.toIso8601String(), end.toIso8601String(), 'void'],
      );
      return (rows.first['value'] as num).toDouble();
    }

    final sales = await documentTotal('sales_invoice');
    final purchases = await documentTotal('purchase_invoice');

    final expenseRows = await db.rawQuery(
      "SELECT COALESCE(SUM(jl.debit-jl.credit),0) AS value "
      "FROM journal_lines jl JOIN journal_entries je ON je.id=jl.entry_id "
      "WHERE jl.account_code LIKE '52%' AND je.date >= ? AND je.date < ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final expenses = (expenseRows.first['value'] as num).toDouble();

    final profitRows = await db.rawQuery(
      "SELECT "
      "COALESCE(SUM(CASE WHEN a.type='revenue' THEN jl.credit-jl.debit ELSE 0 END),0) - "
      "COALESCE(SUM(CASE WHEN a.type='expense' THEN jl.debit-jl.credit ELSE 0 END),0) AS value "
      "FROM journal_lines jl "
      "JOIN journal_entries je ON je.id=jl.entry_id "
      "JOIN accounts a ON a.code=jl.account_code "
      "WHERE je.date >= ? AND je.date < ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final profit = (profitRows.first['value'] as num).toDouble();

    final recentRows = await db.query(
      'documents',
      where: "type IN ('sales_invoice','quotation','receipt_voucher','purchase_invoice')",
      orderBy: 'date DESC, id DESC',
      limit: 4,
    );
    final recent = recentRows
        .map(
          (row) => RecentOperation(
            type: row['type']! as String,
            number: row['number']! as String,
            date: DateTime.parse(row['date']! as String),
            partyName: row['party_name'] as String? ?? 'بدون اسم',
            total: (row['total'] as num).toDouble(),
            status: row['status']! as String,
          ),
        )
        .toList(growable: false);

    return DashboardSnapshot(
      sales: sales,
      purchases: purchases,
      expenses: expenses,
      profit: profit,
      recent: recent,
    );
  }

  Future<List<PartyRecord>> listParties(String type) async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    final rows = await db.query(
      'parties',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'name',
    );
    return rows.map(PartyRecord.fromMap).toList(growable: false);
  }

  Future<int> addParty({
    required String type,
    required String name,
    String? vatNumber,
    String? commercialRegistration,
    String? phone,
    double creditLimit = 0,
    double openingBalance = 0,
  }) async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final id = await txn.insert('parties', {
        'type': type,
        'name': name.trim(),
        'vat_number': policy.isTaxEnabled ? _emptyToNull(vatNumber) : null,
        'commercial_registration': _emptyToNull(commercialRegistration),
        'phone': _emptyToNull(phone),
        'credit_limit': creditLimit,
        'opening_balance': openingBalance,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (openingBalance != 0) {
        await txn.insert('party_movements', {
          'party_id': id,
          'date': DateTime.now().toUtc().toIso8601String(),
          'reference': 'OPENING',
          'operation_type': 'رصيد افتتاحي',
          'debit': type == 'customer' && openingBalance > 0 ? openingBalance : 0,
          'credit': type == 'supplier' && openingBalance > 0 ? openingBalance : 0,
        });
      }
      return id;
    });
  }

  Future<List<ItemRecord>> listItems() async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    final rows = await db.query('items', orderBy: 'name');
    return rows.map(ItemRecord.fromMap).toList(growable: false);
  }

  Future<int> addItem({
    required String code,
    required String name,
    String? barcode,
    double purchasePrice = 0,
    double salePrice = 0,
    double quantity = 0,
    double reorderLevel = 0,
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.insert('items', {
      'code': code.trim(),
      'barcode': _emptyToNull(barcode),
      'name': name.trim(),
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'quantity': quantity,
      'reorder_level': reorderLevel,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> createSalesInvoice({
    required List<InvoiceLineInput> lines,
    required bool onCredit,
    int? customerId,
    String? customerName,
    String? buyerVatNumber,
    String? buyerCommercialRegistration,
    bool b2b = false,
    int? linkedQuotationId,
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Invoice requires at least one line');
    }
    if (onCredit && customerId == null) {
      throw const FormatException('Credit invoice requires a registered customer');
    }

    final policy = await SindarDatabase.instance.getLicensePolicy();
    final number = await _nextNumber('sales_invoice', 'INV');
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();
    final normalized = [
      for (final line in lines)
        InvoiceLineInput(
          itemId: line.itemId,
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          vatRate: policy.isTaxEnabled ? 0.15 : 0,
        ),
    ];
    final net = normalized.fold<double>(0, (sum, line) => sum + line.net);
    final vat = normalized.fold<double>(0, (sum, line) => sum + line.vat);
    final total = net + vat;

    return db.transaction((txn) async {
      if (b2b && policy.isTaxEnabled) {
        final vatValue = buyerVatNumber?.trim() ?? '';
        if (!RegExp(r'^\d{15}$').hasMatch(vatValue)) {
          throw const FormatException('B2B requires a valid 15-digit buyer VAT number');
        }
      }
      await _ensureStock(txn, normalized);

      final id = await txn.insert('documents', {
        'type': 'sales_invoice',
        'number': number,
        'date': now.toIso8601String(),
        'party_id': customerId,
        'party_name': _emptyToNull(customerName),
        'party_vat_number': policy.isTaxEnabled ? _emptyToNull(buyerVatNumber) : null,
        'party_commercial_registration': b2b ? _emptyToNull(buyerCommercialRegistration) : null,
        'payment_method': onCredit ? 'credit' : 'cash',
        'status': 'approved',
        'subtotal': net,
        'vat_total': vat,
        'total': total,
        'paid_amount': onCredit ? 0 : total,
        'currency_code': policy.currencyCode,
        'linked_document_id': linkedQuotationId,
        'created_at': now.toIso8601String(),
      });
      await _insertLines(txn, id, normalized);
      for (final line in normalized) {
        if (line.itemId != null) {
          await txn.rawUpdate(
            'UPDATE items SET quantity = quantity - ? WHERE id = ?',
            [line.quantity, line.itemId],
          );
        }
      }
      await _postJournalTxn(
        txn,
        AutomaticPosting.sales(
          date: now,
          referenceId: id,
          net: net,
          vat: vat,
          onCredit: onCredit,
        ),
      );
      if (onCredit && customerId != null) {
        await txn.insert('party_movements', {
          'party_id': customerId,
          'date': now.toIso8601String(),
          'reference': number,
          'operation_type': 'فاتورة مبيعات',
          'debit': total,
          'credit': 0,
          'document_id': id,
        });
      }
      if (linkedQuotationId != null) {
        await txn.update(
          'documents',
          {'status': 'converted'},
          where: 'id = ?',
          whereArgs: [linkedQuotationId],
        );
      }
      return id;
    });
  }

  Future<int> createQuotation({
    required List<InvoiceLineInput> lines,
    int? customerId,
    String? customerName,
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Quotation requires at least one line');
    }
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final number = await _nextNumber('quotation', 'QUO');
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();
    final normalized = [
      for (final line in lines)
        InvoiceLineInput(
          itemId: line.itemId,
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          vatRate: policy.isTaxEnabled ? 0.15 : 0,
        ),
    ];
    final net = normalized.fold<double>(0, (sum, line) => sum + line.net);
    final vat = normalized.fold<double>(0, (sum, line) => sum + line.vat);
    final total = net + vat;
    return db.transaction((txn) async {
      final id = await txn.insert('documents', {
        'type': 'quotation',
        'number': number,
        'date': now.toIso8601String(),
        'party_id': customerId,
        'party_name': _emptyToNull(customerName),
        'payment_method': 'cash',
        'status': 'open',
        'subtotal': net,
        'vat_total': vat,
        'total': total,
        'paid_amount': 0,
        'currency_code': policy.currencyCode,
        'created_at': now.toIso8601String(),
      });
      await _insertLines(txn, id, normalized);
      return id;
    });
  }

  Future<int> convertQuotationToInvoice(
    int quotationId, {
    required bool onCredit,
  }) async {
    final db = await SindarDatabase.instance.database;
    final docs = await db.query(
      'documents',
      where: 'id = ? AND type = ?',
      whereArgs: [quotationId, 'quotation'],
      limit: 1,
    );
    if (docs.isEmpty) throw const FormatException('Quotation not found');
    final q = docs.first;
    final rows = await db.query(
      'document_lines',
      where: 'document_id = ?',
      whereArgs: [quotationId],
    );
    final lines = rows
        .map(
          (row) => InvoiceLineInput(
            itemId: row['item_id'] as int?,
            description: row['description']! as String,
            quantity: (row['quantity'] as num).toDouble(),
            unitPrice: (row['unit_price'] as num).toDouble(),
          ),
        )
        .toList(growable: false);
    return createSalesInvoice(
      lines: lines,
      onCredit: onCredit,
      customerId: q['party_id'] as int?,
      customerName: q['party_name'] as String?,
      buyerVatNumber: q['party_vat_number'] as String?,
      buyerCommercialRegistration: q['party_commercial_registration'] as String?,
      linkedQuotationId: quotationId,
    );
  }

  Future<List<Map<String, Object?>>> listQuotations() async {
    final db = await SindarDatabase.instance.database;
    return db.query(
      'documents',
      where: 'type = ?',
      whereArgs: ['quotation'],
      orderBy: 'date DESC',
    );
  }

  Future<int> createPurchase({
    required List<InvoiceLineInput> lines,
    required bool onCredit,
    int? supplierId,
    String? supplierName,
    String? supplierVatNumber,
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Purchase requires at least one line');
    }
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final number = await _nextNumber('purchase_invoice', 'PUR');
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();
    final normalized = [
      for (final line in lines)
        InvoiceLineInput(
          itemId: line.itemId,
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          vatRate: policy.isTaxEnabled ? line.vatRate : 0,
        ),
    ];
    final net = normalized.fold<double>(0, (sum, line) => sum + line.net);
    final vat = normalized.fold<double>(0, (sum, line) => sum + line.vat);
    final total = net + vat;

    return db.transaction((txn) async {
      final id = await txn.insert('documents', {
        'type': 'purchase_invoice',
        'number': number,
        'date': now.toIso8601String(),
        'party_id': supplierId,
        'party_name': _emptyToNull(supplierName),
        'party_vat_number': policy.isTaxEnabled ? _emptyToNull(supplierVatNumber) : null,
        'payment_method': onCredit ? 'credit' : 'cash',
        'status': 'approved',
        'subtotal': net,
        'vat_total': vat,
        'total': total,
        'paid_amount': onCredit ? 0 : total,
        'currency_code': policy.currencyCode,
        'created_at': now.toIso8601String(),
      });
      await _insertLines(txn, id, normalized);
      for (final line in normalized) {
        if (line.itemId != null) {
          await txn.rawUpdate(
            'UPDATE items SET quantity = quantity + ?, purchase_price = ? WHERE id = ?',
            [line.quantity, line.unitPrice, line.itemId],
          );
        }
      }
      await _postJournalTxn(
        txn,
        AutomaticPosting.purchase(
          date: now,
          referenceId: id,
          net: net,
          vat: vat,
          onCredit: onCredit,
        ),
      );
      if (onCredit && supplierId != null) {
        await txn.insert('party_movements', {
          'party_id': supplierId,
          'date': now.toIso8601String(),
          'reference': number,
          'operation_type': 'فاتورة مشتريات',
          'debit': 0,
          'credit': total,
          'document_id': id,
        });
      }
      return id;
    });
  }

  Future<int> createVoucher({
    required bool receipt,
    required double amount,
    int? partyId,
    String? partyName,
    String? notes,
  }) async {
    if (amount <= 0) throw const FormatException('Amount must be positive');
    final type = receipt ? 'receipt_voucher' : 'payment_voucher';
    final prefix = receipt ? 'REC' : 'PAY';
    final number = await _nextNumber(type, prefix);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();
    return db.transaction((txn) async {
      final id = await txn.insert('documents', {
        'type': type,
        'number': number,
        'date': now.toIso8601String(),
        'party_id': partyId,
        'party_name': _emptyToNull(partyName),
        'payment_method': 'cash',
        'status': 'approved',
        'subtotal': amount,
        'vat_total': 0,
        'total': amount,
        'paid_amount': amount,
        'currency_code': policy.currencyCode,
        'notes': _emptyToNull(notes),
        'created_at': now.toIso8601String(),
      });
      await _postJournalTxn(
        txn,
        receipt
            ? AutomaticPosting.receipt(
                date: now,
                referenceId: id,
                amount: amount,
              )
            : AutomaticPosting.payment(
                date: now,
                referenceId: id,
                amount: amount,
              ),
      );
      if (partyId != null) {
        await txn.insert('party_movements', {
          'party_id': partyId,
          'date': now.toIso8601String(),
          'reference': number,
          'operation_type': receipt ? 'سند قبض' : 'سند صرف',
          'debit': receipt ? 0 : amount,
          'credit': receipt ? amount : 0,
          'document_id': id,
        });
      }
      return id;
    });
  }

  Future<int> postJournal(JournalDraft draft) async {
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) => _postJournalTxn(txn, draft));
  }

  static Future<int> _postJournalTxn(
    DatabaseExecutor txn,
    JournalDraft draft,
  ) async {
    draft.validate();
    final entryId = await txn.insert('journal_entries', {
      'date': draft.date.toUtc().toIso8601String(),
      'reference_type': draft.referenceType,
      'reference_id': draft.referenceId,
      'description': draft.description,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    for (final line in draft.lines) {
      await txn.insert('journal_lines', {
        'entry_id': entryId,
        'account_code': line.accountCode,
        'debit': line.debit,
        'credit': line.credit,
        'memo': line.memo,
      });
    }
    return entryId;
  }

  Future<List<StatementRow>> partyStatement(
    int partyId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await SindarDatabase.instance.database;
    final where = <String>['party_id = ?'];
    final args = <Object?>[partyId];
    if (from != null) {
      where.add('date >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('date < ?');
      args.add(to.toUtc().add(const Duration(days: 1)).toIso8601String());
    }
    final rows = await db.query(
      'party_movements',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date ASC, id ASC',
    );
    var balance = 0.0;
    final result = <StatementRow>[];
    for (final row in rows) {
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      balance += debit - credit;
      result.add(
        StatementRow(
          date: DateTime.parse(row['date']! as String),
          reference: row['reference']! as String,
          operationType: row['operation_type']! as String,
          debit: debit,
          credit: credit,
          balance: balance,
        ),
      );
    }
    return result;
  }

  Future<List<Map<String, Object?>>> unpaidInvoices(int customerId) async {
    final db = await SindarDatabase.instance.database;
    return db.rawQuery(
      "SELECT *, total-paid_amount AS outstanding FROM documents "
      "WHERE type='sales_invoice' AND party_id=? AND total>paid_amount "
      "AND status!='void' ORDER BY date",
      [customerId],
    );
  }

  Future<int> addAsset({
    required String name,
    required double value,
    required DateTime purchaseDate,
    required double annualDepreciationRate,
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final id = await txn.insert('assets', {
        'name': name.trim(),
        'value': value,
        'purchase_date': purchaseDate.toUtc().toIso8601String(),
        'annual_depreciation_rate': annualDepreciationRate,
        'depreciation_account': '5206',
        'status': 'active',
      });
      await _postJournalTxn(
        txn,
        JournalDraft(
          date: purchaseDate,
          description: 'شراء أصل ثابت: ' + name.trim(),
          referenceType: 'asset',
          referenceId: id,
          lines: [
            JournalLineDraft(accountCode: '1205', debit: value),
            JournalLineDraft(accountCode: '1101', credit: value),
          ],
        ),
      );
      return id;
    });
  }

  Future<List<Map<String, Object?>>> listAssets() async {
    final db = await SindarDatabase.instance.database;
    return db.query('assets', orderBy: 'purchase_date DESC');
  }

  Future<int> addCustody({
    required int employeeId,
    required String kind,
    required String description,
    double amount = 0,
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.insert('custody', {
      'employee_id': employeeId,
      'kind': kind,
      'description': description.trim(),
      'amount': amount,
      'status': 'issued',
      'issued_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> addEmployee({
    required String name,
    required double basicSalary,
    double allowances = 0,
    double advances = 0,
    double deductions = 0,
    double overtime = 0,
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.insert('employees', {
      'name': name.trim(),
      'basic_salary': basicSalary,
      'allowances': allowances,
      'advances': advances,
      'deductions': deductions,
      'overtime': overtime,
      'active': 1,
    });
  }

  Future<List<Map<String, Object?>>> listEmployees() async {
    final db = await SindarDatabase.instance.database;
    return db.query('employees', where: 'active = 1', orderBy: 'name');
  }

  Future<int> runPayroll(String monthKey) async {
    final db = await SindarDatabase.instance.database;
    final employees = await db.query('employees', where: 'active = 1');
    if (employees.isEmpty) {
      throw const FormatException('No active employees');
    }
    double gross = 0;
    double deductions = 0;
    for (final employee in employees) {
      gross +=
          (employee['basic_salary'] as num).toDouble() +
          (employee['allowances'] as num).toDouble() +
          (employee['overtime'] as num).toDouble();
      deductions +=
          (employee['advances'] as num).toDouble() +
          (employee['deductions'] as num).toDouble();
    }
    final net = gross - deductions;
    if (net < 0) throw const FormatException('Payroll net cannot be negative');

    return db.transaction((txn) async {
      final existing = await txn.query(
        'payroll_runs',
        where: 'month_key = ?',
        whereArgs: [monthKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const FormatException('Payroll for this month is already posted');
      }
      final id = await txn.insert('payroll_runs', {
        'month_key': monthKey,
        'gross': gross,
        'deductions': deductions,
        'net': net,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _postJournalTxn(
        txn,
        AutomaticPosting.payroll(
          date: DateTime.now().toUtc(),
          referenceId: id,
          grossExpense: gross,
          netPaid: net,
          deductions: deductions,
        ),
      );
      final policy = await SindarDatabase.instance.getLicensePolicy();
      for (final employee in employees) {
        final empGross =
            (employee['basic_salary'] as num).toDouble() +
            (employee['allowances'] as num).toDouble() +
            (employee['overtime'] as num).toDouble();
        final empDeductions =
            (employee['advances'] as num).toDouble() +
            (employee['deductions'] as num).toDouble();
        final empNet = empGross - empDeductions;
        final voucherNumber = 'PAY-' + monthKey.replaceAll('-', '') + '-' +
            (employee['id'] as int).toString().padLeft(3, '0');
        await txn.insert('documents', {
          'type': 'payment_voucher',
          'number': voucherNumber,
          'date': DateTime.now().toUtc().toIso8601String(),
          'party_name': employee['name']! as String,
          'payment_method': 'cash',
          'status': 'approved',
          'subtotal': empNet,
          'vat_total': 0,
          'total': empNet,
          'paid_amount': empNet,
          'currency_code': policy.currencyCode,
          'notes': 'صرف راتب ' + monthKey,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return id;
    });
  }

  Future<FinancialReportSnapshot> financialReport() async {
    await initialize();
    final db = await SindarDatabase.instance.database;

    Future<double> scalar(String sql, [List<Object?> args = const []]) async {
      final rows = await db.rawQuery(sql, args);
      return (rows.first.values.first as num?)?.toDouble() ?? 0;
    }

    final revenue = await scalar(
      "SELECT COALESCE(SUM(jl.credit-jl.debit),0) FROM journal_lines jl "
      "JOIN accounts a ON a.code=jl.account_code WHERE a.type='revenue'",
    );
    final costOfSales = await scalar(
      "SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code='5101'",
    );
    final operatingExpenses = await scalar(
      "SELECT COALESCE(SUM(jl.debit-jl.credit),0) FROM journal_lines jl "
      "JOIN accounts a ON a.code=jl.account_code "
      "WHERE a.type='expense' AND jl.account_code!='5101'",
    );
    final receivables = await scalar(
      "SELECT COALESCE(SUM(pm.debit-pm.credit),0) FROM party_movements pm "
      "JOIN parties p ON p.id=pm.party_id WHERE p.type='customer'",
    );
    final payables = await scalar(
      "SELECT COALESCE(SUM(pm.credit-pm.debit),0) FROM party_movements pm "
      "JOIN parties p ON p.id=pm.party_id WHERE p.type='supplier'",
    );
    final salesVat = await scalar(
      "SELECT COALESCE(SUM(vat_total),0) FROM documents "
      "WHERE type='sales_invoice' AND status!='void'",
    );
    final purchaseVat = await scalar(
      "SELECT COALESCE(SUM(vat_total),0) FROM documents "
      "WHERE type='purchase_invoice' AND status!='void'",
    );
    final cashBalance = await scalar(
      "SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code='1101'",
    );
    final bankBalance = await scalar(
      "SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code='1102'",
    );

    final trialRows = await db.rawQuery(
      "SELECT a.code,a.name_ar, "
      "COALESCE(SUM(jl.debit),0) debit, COALESCE(SUM(jl.credit),0) credit "
      "FROM accounts a LEFT JOIN journal_lines jl ON jl.account_code=a.code "
      "WHERE a.is_posting=1 GROUP BY a.code,a.name_ar "
      "HAVING debit!=0 OR credit!=0 ORDER BY a.code",
    );
    final trial = trialRows
        .map(
          (row) => TrialBalanceRow(
            code: row['code']! as String,
            name: row['name_ar']! as String,
            debit: (row['debit'] as num).toDouble(),
            credit: (row['credit'] as num).toDouble(),
          ),
        )
        .toList(growable: false);

    return FinancialReportSnapshot(
      revenue: revenue,
      costOfSales: costOfSales,
      operatingExpenses: operatingExpenses,
      netProfit: revenue - costOfSales - operatingExpenses,
      receivables: receivables,
      payables: payables,
      salesVat: salesVat,
      purchaseVat: purchaseVat,
      cashBalance: cashBalance,
      bankBalance: bankBalance,
      trialBalance: trial,
    );
  }

  Future<List<AppUserRecord>> listUsers() async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    final rows = await db.query('users', orderBy: 'id');
    return rows.map(AppUserRecord.fromMap).toList(growable: false);
  }

  Future<int> createUser({
    required String name,
    required String role,
    required String loginCode,
    required String pin,
    required List<PermissionSet> permissions,
  }) async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final count = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM users WHERE active = 1',
            ),
          ) ??
          0;
      if (count >= policy.maxUsers) {
        throw FormatException(
          'تم الوصول إلى الحد الأقصى للمستخدمين: ' + policy.maxUsers.toString(),
        );
      }
      final id = await txn.insert('users', {
        'name': name.trim(),
        'role': role,
        'login_code': loginCode.trim(),
        'pin_hash': _hashPin(pin),
        'active': 1,
        'is_system_admin': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final permission in permissions) {
        await txn.insert('user_permissions', {
          'user_id': id,
          'module': permission.module,
          'can_view': permission.canView ? 1 : 0,
          'can_add': permission.canAdd ? 1 : 0,
          'can_edit': permission.canEdit ? 1 : 0,
          'can_delete': permission.canDelete ? 1 : 0,
          'can_approve': permission.canApprove ? 1 : 0,
          'can_print': permission.canPrint ? 1 : 0,
          'can_view_profit': permission.canViewProfit ? 1 : 0,
        });
      }
      return id;
    });
  }

  Future<AppUserRecord?> authenticate(String loginCode, String pin) async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    final rows = await db.query(
      'users',
      where: 'login_code = ? AND pin_hash = ? AND active = 1',
      whereArgs: [loginCode.trim(), _hashPin(pin)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUserRecord.fromMap(rows.first);
  }

  Future<void> applyLicenseToken(String token) async {
    final grant = LicenseTokenCodec.decodeAndVerify(
      token: token,
      signingSecret: licenseSigningSecret,
    );
    if (!grant.canOperate) {
      throw const FormatException('الترخيص موقوف أو منتهي');
    }
    await SindarDatabase.instance.saveLicensePolicy(grant.policy);
    await SindarDatabase.instance.saveSetting(
      'license_grant',
      jsonEncode(grant.toJson()),
    );
    await SindarDatabase.instance.saveSetting('license_token', token);
  }

  Future<LicenseGrant?> currentLicenseGrant() async {
    final raw = await SindarDatabase.instance.getSetting('license_grant');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return LicenseGrant.fromJson(decoded);
  }

  Future<String> _nextNumber(String type, String prefix) async {
    final next = await SindarDatabase.instance.nextDocumentNumber(type);
    return prefix + '-' + next.toString().padLeft(6, '0');
  }

  static Future<void> _insertLines(
    DatabaseExecutor txn,
    int documentId,
    List<InvoiceLineInput> lines,
  ) async {
    for (final line in lines) {
      if (line.quantity <= 0 || line.unitPrice < 0) {
        throw const FormatException('Invalid line quantity or price');
      }
      await txn.insert('document_lines', {
        'document_id': documentId,
        'item_id': line.itemId,
        'description': line.description.trim(),
        'quantity': line.quantity,
        'unit_price': line.unitPrice,
        'vat_rate': line.vatRate,
        'line_net': line.net,
        'line_vat': line.vat,
        'line_total': line.total,
      });
    }
  }

  static Future<void> _ensureStock(
    DatabaseExecutor txn,
    List<InvoiceLineInput> lines,
  ) async {
    for (final line in lines) {
      if (line.itemId == null) continue;
      final rows = await txn.query(
        'items',
        columns: ['quantity', 'name'],
        where: 'id = ?',
        whereArgs: [line.itemId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const FormatException('Inventory item not found');
      }
      final available = (rows.first['quantity'] as num).toDouble();
      if (available + 0.0001 < line.quantity) {
        throw FormatException(
          'الكمية غير كافية للصنف: ' + (rows.first['name']! as String),
        );
      }
    }
  }

  static String _hashPin(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
