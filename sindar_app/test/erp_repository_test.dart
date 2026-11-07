// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sindar_app/src/data/local/sindar_database.dart';
import 'package:sindar_app/src/services/erp_repository.dart';
import 'package:sindar_app/src/services/operational_models.dart';
import 'package:sindar_core/sindar_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> resetDatabase() async {
    await SindarDatabase.instance.close();
    final root = await getDatabasesPath();
    await deleteDatabase(p.join(root, 'sindar.db'));
  }

  Future<void> activate({
    bool tax = true,
    int maxUsers = 5,
  }) async {
    final grant = LicenseGrant(
      organizationName: 'منشأة الاختبار',
      licenseNumber: 'LIC-TEST',
      expiresAt: DateTime.utc(2035, 1, 1),
      isActive: true,
      policy: LicensePolicy(
        customerId: 'LIC-TEST',
        isTaxEnabled: tax,
        countryCode: 'SA',
        currencyCode: 'SAR',
        currencySymbol: 'ر.س',
        maxUsers: maxUsers,
      ),
    );
    final token = LicenseTokenCodec.encode(
      grant: grant,
      signingSecret: ErpRepository.licenseSigningSecret,
    );
    await ErpRepository.instance.applyLicenseToken(token);
  }

  Future<ItemRecord> addStockItem() async {
    await ErpRepository.instance.addItem(
      code: 'SKU-001',
      barcode: '6281000001118',
      name: 'صنف اختبار فعلي',
      purchasePrice: 50,
      salePrice: 75,
      quantity: 100,
      reorderLevel: 5,
    );
    return (await ErpRepository.instance.listItems())
        .firstWhere((item) => item.code == 'SKU-001');
  }

  setUp(resetDatabase);
  tearDown(() async => SindarDatabase.instance.close());

  test('fresh production database contains no demo operations', () async {
    final snapshot = await ErpRepository.instance.dashboard(
      year: 2026,
      month: 11,
    );

    expect(snapshot.sales, 0);
    expect(snapshot.purchases, 0);
    expect(snapshot.expenses, 0);
    expect(snapshot.profit, 0);
    expect(snapshot.recent, isEmpty);
    expect(await ErpRepository.instance.listItems(), isEmpty);
    expect(await ErpRepository.instance.listParties('customer'), isEmpty);
    expect(await ErpRepository.instance.listParties('supplier'), isEmpty);
  });

  test('approved bank sale updates stock and posts revenue VAT and COGS', () async {
    await activate();
    final item = await addStockItem();
    final beforeQty = item.quantity;

    final invoiceId = await ErpRepository.instance.createSalesInvoice(
      lines: [
        InvoiceLineInput(
          itemId: item.id,
          description: item.name,
          quantity: 2,
          unitPrice: 75,
          vatRate: .15,
        ),
      ],
      onCredit: false,
      settlementAccountCode: '1102',
    );

    final db = await SindarDatabase.instance.database;
    final refreshed = await db.query(
      'items',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    expect(
      (refreshed.first['quantity'] as num).toDouble(),
      closeTo(beforeQty - 2, .001),
    );

    final lines = await db.rawQuery(
      'SELECT jl.account_code, SUM(jl.debit) debit, SUM(jl.credit) credit '
      'FROM journal_lines jl '
      'JOIN journal_entries je ON je.id=jl.entry_id '
      'WHERE je.reference_id=? '
      "AND je.reference_type IN ('sales_invoice','sales_cogs') "
      'GROUP BY jl.account_code',
      [invoiceId],
    );
    final byAccount = {
      for (final row in lines) row['account_code']! as String: row,
    };

    expect((byAccount['1102']!['debit'] as num).toDouble(), closeTo(172.5, .001));
    expect((byAccount['4101']!['credit'] as num).toDouble(), closeTo(150, .001));
    expect((byAccount['2102']!['credit'] as num).toDouble(), closeTo(22.5, .001));
    expect((byAccount['5101']!['debit'] as num).toDouble(), closeTo(100, .001));
    expect((byAccount['1104']!['credit'] as num).toDouble(), closeTo(100, .001));
  });

  test('transient supplier cannot be used for credit purchase', () async {
    await activate();

    expect(
      () => ErpRepository.instance.createPurchase(
        lines: const [
          InvoiceLineInput(
            description: 'شراء عابر',
            quantity: 1,
            unitPrice: 100,
            vatRate: .15,
          ),
        ],
        onCredit: true,
        supplierName: 'مورد عابر',
      ),
      throwsFormatException,
    );
  });

  test('maxUsers is enforced by the licensed policy', () async {
    await activate(maxUsers: 5);
    for (var i = 1; i <= 4; i++) {
      await ErpRepository.instance.createUser(
        name: 'مستخدم ' + i.toString(),
        role: 'cashier',
        loginCode: 'cashier' + i.toString(),
        pin: '12' + i.toString() + '4',
        permissions: const [
          PermissionSet(
            module: 'sales',
            canView: true,
            canAdd: true,
          ),
        ],
      );
    }

    expect(
      () => ErpRepository.instance.createUser(
        name: 'مستخدم زائد',
        role: 'cashier',
        loginCode: 'overflow',
        pin: '9999',
        permissions: const [],
      ),
      throwsFormatException,
    );
  });

  test('editing a sale reverses old stock and journals before reposting', () async {
    await activate();
    final item = await addStockItem();
    final beforeQty = item.quantity;

    final invoiceId = await ErpRepository.instance.createSalesInvoice(
      lines: [
        InvoiceLineInput(
          itemId: item.id,
          description: item.name,
          quantity: 2,
          unitPrice: 75,
          vatRate: .15,
        ),
      ],
      onCredit: false,
      settlementAccountCode: '1102',
    );

    await ErpRepository.instance.updateSalesInvoice(
      invoiceId: invoiceId,
      lines: [
        InvoiceLineInput(
          itemId: item.id,
          description: item.name,
          quantity: 1,
          unitPrice: 75,
          vatRate: .15,
        ),
      ],
      onCredit: false,
      settlementAccountCode: '1101',
    );

    final db = await SindarDatabase.instance.database;
    final stock = await db.query(
      'items',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    expect(
      (stock.first['quantity'] as num).toDouble(),
      closeTo(beforeQty - 1, .001),
    );

    final bank = await db.rawQuery(
      'SELECT COALESCE(SUM(jl.debit-jl.credit),0) value '
      'FROM journal_lines jl JOIN journal_entries je ON je.id=jl.entry_id '
      "WHERE je.reference_id=? AND jl.account_code='1102'",
      [invoiceId],
    );
    final cash = await db.rawQuery(
      'SELECT COALESCE(SUM(jl.debit-jl.credit),0) value '
      'FROM journal_lines jl JOIN journal_entries je ON je.id=jl.entry_id '
      "WHERE je.reference_id=? AND jl.account_code='1101'",
      [invoiceId],
    );
    expect((bank.first['value'] as num).toDouble(), closeTo(0, .001));
    expect((cash.first['value'] as num).toDouble(), closeTo(86.25, .001));
  });
}
