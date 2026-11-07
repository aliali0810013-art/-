// ignore_for_file: prefer_interpolation_to_compose_strings

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
    await _purgeLegacyDemoData(db);

    final grant = await currentLicenseGrant();
    if (grant?.canOperate == true) {
      await _ensureSystemAdmin(db);
    }
  }

  Future<void> _ensureSystemAdmin(DatabaseExecutor db) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE is_system_admin = 1',
          ),
        ) ??
        0;
    if (count > 0) return;

    await db.insert('users', {
      'name': 'مدير النظام',
      'role': 'admin',
      'login_code': 'admin',
      'pin_hash': _hashPin('1234'),
      'active': 1,
      'is_system_admin': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _purgeLegacyDemoData(Database db) async {
    final cleaned = await SindarDatabase.instance.getSetting(
      'production_cleaned_v1',
    );
    if (cleaned == 'true') return;

    final demoSeeded = await SindarDatabase.instance.getSetting(
      'demo_seeded_v2',
    );
    if (demoSeeded == 'true') {
      await db.transaction((txn) async {
        const demoNumbers = <String>[
          'INV-000245',
          'INV-000244',
          'QUO-000128',
          'REC-000067',
          'PUR-000097',
          'PUR-000096',
        ];
        final placeholders = List.filled(
          demoNumbers.length,
          '?',
        ).join(',');

        await txn.rawDelete(
          'DELETE FROM journal_lines WHERE entry_id IN ('
          'SELECT id FROM journal_entries WHERE '
          "reference_type IN ('demo_cogs','demo_expense') OR "
          '(reference_id IN (SELECT id FROM documents '
          'WHERE number IN (' + placeholders + ')) AND '
          "reference_type IN ('sales_invoice','sales_cogs',"
          "'purchase_invoice','receipt_voucher')))",
          demoNumbers,
        );
        await txn.rawDelete(
          'DELETE FROM journal_entries WHERE '
          "reference_type IN ('demo_cogs','demo_expense') OR "
          '(reference_id IN (SELECT id FROM documents '
          'WHERE number IN (' + placeholders + ')) AND '
          "reference_type IN ('sales_invoice','sales_cogs',"
          "'purchase_invoice','receipt_voucher'))",
          demoNumbers,
        );
        await txn.rawDelete(
          'DELETE FROM party_movements WHERE '
          'document_id IN (SELECT id FROM documents '
          'WHERE number IN (' + placeholders + ')) OR '
          'reference IN (' + placeholders + ')',
          <Object?>[...demoNumbers, ...demoNumbers],
        );
        await txn.rawDelete(
          'DELETE FROM document_lines WHERE document_id IN ('
          'SELECT id FROM documents WHERE number IN (' +
              placeholders +
              '))',
          demoNumbers,
        );
        await txn.rawDelete(
          'DELETE FROM documents WHERE number IN (' +
              placeholders +
              ')',
          demoNumbers,
        );
        await txn.rawDelete(
          "DELETE FROM items WHERE code = ? AND name = ? "
          'AND id NOT IN (SELECT item_id FROM document_lines '
          'WHERE item_id IS NOT NULL)',
          ['ITM-001', 'صنف تجريبي رئيسي'],
        );
        await txn.rawDelete(
          "DELETE FROM parties WHERE name IN (?, ?) "
          'AND id NOT IN (SELECT party_id FROM documents '
          'WHERE party_id IS NOT NULL) '
          'AND id NOT IN (SELECT party_id FROM party_movements)',
          ['شركة الواجهة الحديثة', 'مؤسسة التوريد الذهبي'],
        );

        const demoSettings = <String, String>{
          'company_name_ar': 'مؤسسة سندار التجارية',
          'company_name_en': 'SINDAR Trading Est.',
          'company_cr': '1010101010',
          'seller_vat_number': '310123456700003',
        };
        for (final entry in demoSettings.entries) {
          await txn.delete(
            'app_settings',
            where: 'setting_key = ? AND setting_value = ?',
            whereArgs: [entry.key, entry.value],
          );
        }

        final grantRows = await txn.query(
          'app_settings',
          columns: ['setting_value'],
          where: 'setting_key = ?',
          whereArgs: ['license_grant'],
          limit: 1,
        );
        if (grantRows.isEmpty) {
          final policyRows = await txn.query(
            'app_settings',
            columns: ['setting_value'],
            where: 'setting_key = ?',
            whereArgs: ['license_policy'],
            limit: 1,
          );
          if (policyRows.isNotEmpty &&
              (policyRows.first['setting_value'] as String)
                  .contains('DEMO-SINDAR')) {
            await txn.delete(
              'app_settings',
              where: 'setting_key = ?',
              whereArgs: ['license_policy'],
            );
          }
        }

        final documentCount = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM documents'),
            ) ??
            0;
        if (documentCount == 0) {
          await txn.update(
            'document_sequences',
            {'next_number': 1},
          );
        }

        await txn.delete(
          'app_settings',
          where: 'setting_key = ?',
          whereArgs: ['demo_seeded_v2'],
        );
      });
    }

    await SindarDatabase.instance.saveSetting(
      'production_cleaned_v1',
      'true',
    );
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

  Future<List<ContactChannel>> footerContacts() async {
    final raw = await SindarDatabase.instance.getSetting('footer_contacts');
    if (raw == null || raw.trim().isEmpty) {
      return const <ContactChannel>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> &&
              item['type'] is String &&
              item['value'] is String)
            ContactChannel(
              type: ContactChannelType.values.byName(item['type']! as String),
              value: item['value']! as String,
              label: item['label'] as String?,
            ),
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> saveFooterContacts(List<ContactChannel> contacts) async {
    await SindarDatabase.instance.saveSetting(
      'footer_contacts',
      jsonEncode([
        for (final contact in contacts)
          {
            'type': contact.type.name,
            'value': contact.value.trim(),
            'label': contact.label,
          },
      ]),
    );
  }

  Future<Map<String, String>> companySettings() async {
    await initialize();
    final db = await SindarDatabase.instance.database;
    const keys = [
      'company_name_ar',
      'company_name_en',
      'company_cr',
      'seller_vat_number',
    ];
    final rows = await db.query(
      'app_settings',
      where: 'setting_key IN (?,?,?,?)',
      whereArgs: keys,
    );
    return {
      for (final row in rows)
        row['setting_key']! as String: row['setting_value']! as String,
    };
  }

  Future<void> saveCompanySettings({
    required String nameAr,
    required String nameEn,
    required String commercialRegistration,
    String? sellerVatNumber,
  }) async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final vat = sellerVatNumber?.trim() ?? '';
    if (nameAr.trim().isEmpty) {
      throw const FormatException('الاسم التجاري العربي مطلوب');
    }
    if (policy.isTaxEnabled &&
        vat.isNotEmpty &&
        (vat.length != 15 || int.tryParse(vat) == null)) {
      throw const FormatException(
        'الرقم الضريبي للبائع يجب أن يكون 15 رقماً',
      );
    }
    final values = <String, String>{
      'company_name_ar': nameAr.trim(),
      'company_name_en': nameEn.trim(),
      'company_cr': commercialRegistration.trim(),
      'seller_vat_number': policy.isTaxEnabled ? vat : '',
    };
    for (final entry in values.entries) {
      await SindarDatabase.instance.saveSetting(entry.key, entry.value);
    }
  }

  Future<Map<String, Object?>> documentById(int id) async {
    final db = await SindarDatabase.instance.database;
    final rows = await db.query(
      'documents',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('Document not found');
    return rows.first;
  }

  Future<List<Map<String, Object?>>> documentLines(int documentId) async {
    final db = await SindarDatabase.instance.database;
    return db.query(
      'document_lines',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id',
    );
  }

  Future<DocumentDraft> documentDraft(int documentId) async {
    final row = await documentById(documentId);
    final lineRows = await documentLines(documentId);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final company = await companySettings();
    final contacts = await footerContacts();
    final rawType = row['type']! as String;

    final type = switch (rawType) {
      'sales_invoice' => policy.isTaxEnabled
          ? ((row['party_vat_number'] as String?)?.isNotEmpty == true
              ? DocumentType.taxInvoice
              : DocumentType.simplifiedTaxInvoice)
          : DocumentType.commercialInvoice,
      'quotation' => DocumentType.quotation,
      'receipt_voucher' => DocumentType.receiptVoucher,
      'payment_voucher' => DocumentType.paymentVoucher,
      'official_letter' => DocumentType.officialLetter,
      'financial_claim' => DocumentType.financialClaim,
      _ => DocumentType.commercialInvoice,
    };

    return DocumentDraft(
      type: type,
      number: row['number']! as String,
      date: DateTime.parse(row['date']! as String),
      company: CompanyProfile(
        nameAr: company['company_name_ar'] ?? 'المنشأة',
        nameEn: company['company_name_en'] ?? '',
        commercialRegistration: company['company_cr'] ?? '',
        vatNumber: policy.isTaxEnabled
            ? _emptyToNull(company['seller_vat_number'])
            : null,
      ),
      lines: [
        for (final line in lineRows)
          DocumentLine(
            description: line['description']! as String,
            quantity: (line['quantity'] as num).toDouble(),
            unitPrice: (line['unit_price'] as num).toDouble(),
            vatRate: policy.isTaxEnabled
                ? (line['vat_rate'] as num).toDouble()
                : 0,
          ),
      ],
      contacts: contacts,
      identity: const DocumentIdentity(),
      partyName: row['party_name'] as String?,
      buyerVatNumber: policy.isTaxEnabled
          ? row['party_vat_number'] as String?
          : null,
      buyerCommercialRegistration: policy.isTaxEnabled
          ? row['party_commercial_registration'] as String?
          : null,
      notes: row['notes'] as String?,
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
    if (type != 'customer' && type != 'supplier') {
      throw const FormatException('Party type must be customer or supplier');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Party name is required');
    }
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final vat = vatNumber?.trim() ?? '';
    if (policy.isTaxEnabled &&
        vat.isNotEmpty &&
        (vat.length != 15 || int.tryParse(vat) == null)) {
      throw const FormatException('الرقم الضريبي يجب أن يكون 15 رقماً');
    }
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();
    return db.transaction((txn) async {
      final id = await txn.insert('parties', {
        'type': type,
        'name': name.trim(),
        'vat_number': policy.isTaxEnabled ? _emptyToNull(vatNumber) : null,
        'commercial_registration': _emptyToNull(commercialRegistration),
        'phone': _emptyToNull(phone),
        'credit_limit': creditLimit,
        'opening_balance': openingBalance,
        'created_at': now.toIso8601String(),
      });

      if (openingBalance != 0) {
        final amount = openingBalance.abs();
        final customer = type == 'customer';
        final debit = customer
            ? (openingBalance > 0 ? amount : 0.0)
            : (openingBalance < 0 ? amount : 0.0);
        final credit = customer
            ? (openingBalance < 0 ? amount : 0.0)
            : (openingBalance > 0 ? amount : 0.0);

        await txn.insert('party_movements', {
          'party_id': id,
          'date': now.toIso8601String(),
          'reference': 'OPENING',
          'operation_type': 'رصيد افتتاحي',
          'debit': debit,
          'credit': credit,
        });

        final partyAccount = customer ? '1103' : '2101';
        final equityAccount = '3103';
        await _postJournalTxn(
          txn,
          JournalDraft(
            date: now,
            description: 'رصيد افتتاحي - ' + name.trim(),
            referenceType: 'party_opening',
            referenceId: id,
            lines: openingBalance > 0
                ? (customer
                    ? [
                        JournalLineDraft(
                          accountCode: partyAccount,
                          debit: amount,
                        ),
                        JournalLineDraft(
                          accountCode: equityAccount,
                          credit: amount,
                        ),
                      ]
                    : [
                        JournalLineDraft(
                          accountCode: equityAccount,
                          debit: amount,
                        ),
                        JournalLineDraft(
                          accountCode: partyAccount,
                          credit: amount,
                        ),
                      ])
                : (customer
                    ? [
                        JournalLineDraft(
                          accountCode: equityAccount,
                          debit: amount,
                        ),
                        JournalLineDraft(
                          accountCode: partyAccount,
                          credit: amount,
                        ),
                      ]
                    : [
                        JournalLineDraft(
                          accountCode: partyAccount,
                          debit: amount,
                        ),
                        JournalLineDraft(
                          accountCode: equityAccount,
                          credit: amount,
                        ),
                      ]),
          ),
        );
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
    String settlementAccountCode = '1101',
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Invoice requires at least one line');
    }
    if (onCredit && customerId == null) {
      throw const FormatException('Credit invoice requires a registered customer');
    }
    if (!onCredit &&
        settlementAccountCode != '1101' &&
        settlementAccountCode != '1102') {
      throw const FormatException('Settlement account must be cash or bank');
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
        final crValue = buyerCommercialRegistration?.trim() ?? '';
        if (vatValue.length != 15 || int.tryParse(vatValue) == null) {
          throw const FormatException(
            'B2B requires a valid 15-digit buyer VAT number',
          );
        }
        if (crValue.isEmpty) {
          throw const FormatException(
            'B2B requires the buyer commercial registration',
          );
        }
      }

      await _ensureStock(txn, normalized);

      var costOfGoodsSold = 0.0;
      for (final line in normalized) {
        final itemId = line.itemId;
        if (itemId == null) continue;
        final itemRows = await txn.query(
          'items',
          columns: ['purchase_price'],
          where: 'id = ?',
          whereArgs: [itemId],
          limit: 1,
        );
        if (itemRows.isNotEmpty) {
          costOfGoodsSold +=
              (itemRows.first['purchase_price'] as num).toDouble() *
              line.quantity;
        }
      }

      final id = await txn.insert('documents', {
        'type': 'sales_invoice',
        'number': number,
        'date': now.toIso8601String(),
        'party_id': customerId,
        'party_name': _emptyToNull(customerName),
        'party_vat_number':
            policy.isTaxEnabled ? _emptyToNull(buyerVatNumber) : null,
        'party_commercial_registration': b2b
            ? _emptyToNull(buyerCommercialRegistration)
            : null,
        'payment_method': onCredit
            ? 'credit'
            : (settlementAccountCode == '1102' ? 'bank' : 'cash'),
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
          settlementAccountCode: settlementAccountCode,
        ),
      );

      if (costOfGoodsSold > 0) {
        await _postJournalTxn(
          txn,
          JournalDraft(
            date: now,
            description: 'تكلفة البضاعة المباعة - ' + number,
            referenceType: 'sales_cogs',
            referenceId: id,
            lines: [
              JournalLineDraft(
                accountCode: '5101',
                debit: costOfGoodsSold,
              ),
              JournalLineDraft(
                accountCode: '1104',
                credit: costOfGoodsSold,
              ),
            ],
          ),
        );
      }

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

  Future<int> saveStandaloneDocument(DocumentDraft draft) async {
    final type = switch (draft.type) {
      DocumentType.officialLetter => 'official_letter',
      DocumentType.financialClaim => 'financial_claim',
      DocumentType.customerStatement => 'customer_statement',
      DocumentType.supplierStatement => 'supplier_statement',
      _ => throw const FormatException(
          'This document type must be saved from its operational screen',
        ),
    };
    final prefix = switch (draft.type) {
      DocumentType.officialLetter => 'LTR',
      DocumentType.financialClaim => 'CLM',
      DocumentType.customerStatement => 'CST',
      DocumentType.supplierStatement => 'SST',
      _ => 'DOC',
    };
    final number = await _nextNumber(type, prefix);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    final safe = draft.sanitizedFor(policy);

    return db.transaction((txn) async {
      final id = await txn.insert('documents', {
        'type': type,
        'number': number,
        'date': safe.date.toUtc().toIso8601String(),
        'party_name': _emptyToNull(safe.partyName),
        'party_vat_number':
            policy.isTaxEnabled ? _emptyToNull(safe.buyerVatNumber) : null,
        'party_commercial_registration': policy.isTaxEnabled
            ? _emptyToNull(safe.buyerCommercialRegistration)
            : null,
        'payment_method': 'none',
        'status': 'approved',
        'subtotal': safe.netTotal,
        'vat_total': safe.vatTotal,
        'total': safe.grandTotal,
        'paid_amount': 0,
        'currency_code': policy.currencyCode,
        'notes': _emptyToNull(safe.notes),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _insertLines(
        txn,
        id,
        [
          for (final line in safe.lines)
            InvoiceLineInput(
              description: line.description,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              vatRate: line.vatRate,
            ),
        ],
      );
      return id;
    });
  }

  Future<List<Map<String, Object?>>> listSalesInvoices({
    int limit = 30,
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.query(
      'documents',
      where: 'type = ? AND status != ?',
      whereArgs: ['sales_invoice', 'void'],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
  }

  Future<int> updateSalesInvoice({
    required int invoiceId,
    required List<InvoiceLineInput> lines,
    required bool onCredit,
    int? customerId,
    String? customerName,
    String? buyerVatNumber,
    String? buyerCommercialRegistration,
    bool b2b = false,
    String settlementAccountCode = '1101',
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Invoice requires at least one line');
    }
    if (onCredit && customerId == null) {
      throw const FormatException(
        'Credit invoice requires a registered customer',
      );
    }
    if (!onCredit &&
        settlementAccountCode != '1101' &&
        settlementAccountCode != '1102') {
      throw const FormatException('Settlement account must be cash or bank');
    }

    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
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
      final docs = await txn.query(
        'documents',
        where: 'id = ? AND type = ? AND status != ?',
        whereArgs: [invoiceId, 'sales_invoice', 'void'],
        limit: 1,
      );
      if (docs.isEmpty) {
        throw const FormatException('Sales invoice not found');
      }
      final old = docs.first;
      final oldPayment = old['payment_method']! as String;
      final oldPaid = (old['paid_amount'] as num).toDouble();
      if (oldPayment == 'credit' && oldPaid > 0.005) {
        throw const FormatException(
          'لا يمكن تعديل فاتورة آجلة بعد تسجيل تحصيل عليها',
        );
      }

      if (b2b && policy.isTaxEnabled) {
        final vatValue = buyerVatNumber?.trim() ?? '';
        final crValue = buyerCommercialRegistration?.trim() ?? '';
        if (vatValue.length != 15 || int.tryParse(vatValue) == null) {
          throw const FormatException(
            'B2B requires a valid 15-digit buyer VAT number',
          );
        }
        if (crValue.isEmpty) {
          throw const FormatException(
            'B2B requires the buyer commercial registration',
          );
        }
      }

      final oldLines = await txn.query(
        'document_lines',
        where: 'document_id = ?',
        whereArgs: [invoiceId],
      );
      for (final row in oldLines) {
        final itemId = row['item_id'] as int?;
        if (itemId != null) {
          await txn.rawUpdate(
            'UPDATE items SET quantity = quantity + ? WHERE id = ?',
            [(row['quantity'] as num).toDouble(), itemId],
          );
        }
      }

      await txn.rawDelete(
        'DELETE FROM journal_lines WHERE entry_id IN ('
        'SELECT id FROM journal_entries WHERE reference_id=? '
        "AND reference_type IN ('sales_invoice','sales_cogs'))",
        [invoiceId],
      );
      await txn.rawDelete(
        'DELETE FROM journal_entries WHERE reference_id=? '
        "AND reference_type IN ('sales_invoice','sales_cogs')",
        [invoiceId],
      );
      await txn.delete(
        'party_movements',
        where: 'document_id = ?',
        whereArgs: [invoiceId],
      );
      await txn.delete(
        'document_lines',
        where: 'document_id = ?',
        whereArgs: [invoiceId],
      );

      await _ensureStock(txn, normalized);

      var costOfGoodsSold = 0.0;
      for (final line in normalized) {
        final itemId = line.itemId;
        if (itemId == null) continue;
        final itemRows = await txn.query(
          'items',
          columns: ['purchase_price'],
          where: 'id = ?',
          whereArgs: [itemId],
          limit: 1,
        );
        if (itemRows.isNotEmpty) {
          costOfGoodsSold +=
              (itemRows.first['purchase_price'] as num).toDouble() *
              line.quantity;
        }
      }

      final date = DateTime.parse(old['date']! as String);
      final number = old['number']! as String;
      await txn.update(
        'documents',
        {
          'party_id': customerId,
          'party_name': _emptyToNull(customerName),
          'party_vat_number':
              policy.isTaxEnabled ? _emptyToNull(buyerVatNumber) : null,
          'party_commercial_registration': b2b
              ? _emptyToNull(buyerCommercialRegistration)
              : null,
          'payment_method': onCredit
              ? 'credit'
              : (settlementAccountCode == '1102' ? 'bank' : 'cash'),
          'subtotal': net,
          'vat_total': vat,
          'total': total,
          'paid_amount': onCredit ? 0 : total,
          'currency_code': policy.currencyCode,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      await _insertLines(txn, invoiceId, normalized);
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
          date: date,
          referenceId: invoiceId,
          net: net,
          vat: vat,
          onCredit: onCredit,
          settlementAccountCode: settlementAccountCode,
        ),
      );
      if (costOfGoodsSold > 0) {
        await _postJournalTxn(
          txn,
          JournalDraft(
            date: date,
            description: 'تكلفة البضاعة المباعة - ' + number,
            referenceType: 'sales_cogs',
            referenceId: invoiceId,
            lines: [
              JournalLineDraft(
                accountCode: '5101',
                debit: costOfGoodsSold,
              ),
              JournalLineDraft(
                accountCode: '1104',
                credit: costOfGoodsSold,
              ),
            ],
          ),
        );
      }

      if (onCredit && customerId != null) {
        await txn.insert('party_movements', {
          'party_id': customerId,
          'date': date.toUtc().toIso8601String(),
          'reference': number,
          'operation_type': 'فاتورة مبيعات',
          'debit': total,
          'credit': 0,
          'document_id': invoiceId,
        });
      }
      return invoiceId;
    });
  }

  Future<int> createQuotation({
    required List<InvoiceLineInput> lines,
    int? customerId,
    String? customerName,
    String? buyerVatNumber,
    String? buyerCommercialRegistration,
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
        'party_vat_number':
            policy.isTaxEnabled ? _emptyToNull(buyerVatNumber) : null,
        'party_commercial_registration': policy.isTaxEnabled
            ? _emptyToNull(buyerCommercialRegistration)
            : null,
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

  Future<List<Map<String, Object?>>> listQuotations() async {
    final db = await SindarDatabase.instance.database;
    return db.query(
      'documents',
      where: 'type = ?',
      whereArgs: ['quotation'],
      orderBy: 'date DESC',
    );
  }

  Future<int> convertQuotationToInvoice(
    int quotationId, {
    required bool onCredit,
    String settlementAccountCode = '1101',
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
    final buyerVat = q['party_vat_number'] as String?;
    final buyerCr = q['party_commercial_registration'] as String?;
    return createSalesInvoice(
      lines: lines,
      onCredit: onCredit,
      customerId: q['party_id'] as int?,
      customerName: q['party_name'] as String?,
      buyerVatNumber: buyerVat,
      buyerCommercialRegistration: buyerCr,
      b2b: buyerVat?.isNotEmpty == true && buyerCr?.isNotEmpty == true,
      linkedQuotationId: quotationId,
      settlementAccountCode: settlementAccountCode,
    );
  }

  Future<int> createPurchase({
    required List<InvoiceLineInput> lines,
    required bool onCredit,
    int? supplierId,
    String? supplierName,
    String? supplierVatNumber,
    String settlementAccountCode = '1101',
  }) async {
    if (lines.isEmpty) {
      throw const FormatException('Purchase requires at least one line');
    }
    if (onCredit && supplierId == null) {
      throw const FormatException(
        'Credit purchase requires a registered supplier',
      );
    }
    if (!onCredit &&
        settlementAccountCode != '1101' &&
        settlementAccountCode != '1102') {
      throw const FormatException('Settlement account must be cash or bank');
    }

    final policy = await SindarDatabase.instance.getLicensePolicy();
    final supplierVat = supplierVatNumber?.trim() ?? '';
    if (policy.isTaxEnabled &&
        supplierVat.isNotEmpty &&
        (supplierVat.length != 15 || int.tryParse(supplierVat) == null)) {
      throw const FormatException('Supplier VAT must contain 15 digits');
    }

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
        'party_vat_number':
            policy.isTaxEnabled ? _emptyToNull(supplierVatNumber) : null,
        'payment_method': onCredit
            ? 'credit'
            : (settlementAccountCode == '1102' ? 'bank' : 'cash'),
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
            'UPDATE items SET quantity = quantity + ?, purchase_price = ? '
            'WHERE id = ?',
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
          settlementAccountCode: settlementAccountCode,
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
    int? linkedDocumentId,
    String? notes,
    String settlementAccountCode = '1101',
  }) async {
    if (amount <= 0) throw const FormatException('Amount must be positive');
    if (settlementAccountCode != '1101' &&
        settlementAccountCode != '1102') {
      throw const FormatException('Settlement account must be cash or bank');
    }
    final type = receipt ? 'receipt_voucher' : 'payment_voucher';
    final prefix = receipt ? 'REC' : 'PAY';
    final number = await _nextNumber(type, prefix);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final db = await SindarDatabase.instance.database;
    final now = DateTime.now().toUtc();

    return db.transaction((txn) async {
      if (linkedDocumentId != null) {
        final linked = await txn.query(
          'documents',
          columns: ['total', 'paid_amount'],
          where: 'id = ?',
          whereArgs: [linkedDocumentId],
          limit: 1,
        );
        if (linked.isEmpty) {
          throw const FormatException('Linked document not found');
        }
        final outstanding =
            (linked.first['total'] as num).toDouble() -
            (linked.first['paid_amount'] as num).toDouble();
        if (amount - outstanding > 0.005) {
          throw const FormatException(
            'Voucher amount exceeds the linked outstanding balance',
          );
        }
      }

      final id = await txn.insert('documents', {
        'type': type,
        'number': number,
        'date': now.toIso8601String(),
        'party_id': partyId,
        'party_name': _emptyToNull(partyName),
        'payment_method':
            settlementAccountCode == '1102' ? 'bank' : 'cash',
        'status': 'approved',
        'subtotal': amount,
        'vat_total': 0,
        'total': amount,
        'paid_amount': amount,
        'currency_code': policy.currencyCode,
        'linked_document_id': linkedDocumentId,
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
                settlementAccountCode: settlementAccountCode,
              )
            : AutomaticPosting.payment(
                date: now,
                referenceId: id,
                amount: amount,
                settlementAccountCode: settlementAccountCode,
              ),
      );

      if (linkedDocumentId != null) {
        await txn.rawUpdate(
          'UPDATE documents SET paid_amount = MIN(total, paid_amount + ?) '
          'WHERE id = ?',
          [amount, linkedDocumentId],
        );
      }

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

  Future<List<Map<String, Object?>>> outstandingDocuments(
    int partyId, {
    required bool receivable,
  }) async {
    final db = await SindarDatabase.instance.database;
    final type = receivable ? 'sales_invoice' : 'purchase_invoice';
    return db.rawQuery(
      'SELECT *, total-paid_amount AS outstanding FROM documents '
      'WHERE type=? AND party_id=? AND total>paid_amount '
      "AND status!='void' ORDER BY date",
      [type, partyId],
    );
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
    String depreciationAccount = '5206',
  }) async {
    final db = await SindarDatabase.instance.database;
    return db.transaction((txn) async {
      final id = await txn.insert('assets', {
        'name': name.trim(),
        'value': value,
        'purchase_date': purchaseDate.toUtc().toIso8601String(),
        'annual_depreciation_rate': annualDepreciationRate,
        'depreciation_account': depreciationAccount.trim().isEmpty
            ? '5206'
            : depreciationAccount.trim(),
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
    if (!grant.policy.isTaxEnabled) {
      await SindarDatabase.instance.saveSetting('seller_vat_number', '');
    }
    await SindarDatabase.instance.saveSetting(
      'license_grant',
      jsonEncode(grant.toJson()),
    );
    await SindarDatabase.instance.saveSetting('license_token', token);
    await _ensureSystemAdmin(await SindarDatabase.instance.database);
  }

  Future<LicenseGrant?> currentLicenseGrant() async {
    final raw = await SindarDatabase.instance.getSetting('license_grant');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return LicenseGrant.fromJson(decoded);
  }

  Future<bool> hasPermission(
    AppUserRecord user,
    String module, {
    String action = 'view',
  }) async {
    if (user.isSystemAdmin) return true;
    const columns = <String, String>{
      'view': 'can_view',
      'add': 'can_add',
      'edit': 'can_edit',
      'delete': 'can_delete',
      'approve': 'can_approve',
      'print': 'can_print',
      'profit': 'can_view_profit',
    };
    final column = columns[action];
    if (column == null) return false;
    final db = await SindarDatabase.instance.database;
    final rows = await db.query(
      'user_permissions',
      columns: [column],
      where: 'user_id = ? AND module = ?',
      whereArgs: [user.id, module],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first[column] as int? ?? 0) == 1;
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
