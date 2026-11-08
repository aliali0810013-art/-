import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sindar_core/sindar_core.dart';

import 'package:sindar_app/src/data/local/sindar_database.dart';
import 'package:sindar_app/src/services/erp_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> reset() async {
    await SindarDatabase.instance.close();
    final root = await getDatabasesPath();
    await deleteDatabase(path.join(root, 'sindar.db'));
  }

  setUp(reset);
  tearDown(() => SindarDatabase.instance.close());

  test('Yemen service invoice remains non-tax and posts service revenue', () async {
    await SindarDatabase.instance.saveLicensePolicy(const LicensePolicy(
      customerId: 'YE-SERVICE',
      isTaxEnabled: true,
      countryCode: 'YE',
      currencyCode: 'YER',
      currencySymbol: 'ر.ي',
      maxUsers: 2,
    ));
    final id = await ErpRepository.instance.createServiceInvoice(
      description: 'صيانة نظام',
      unitPrice: 1000,
      onCredit: false,
      applyTax: true,
    );
    final db = await SindarDatabase.instance.database;
    final doc = (await db.query('documents',
      where: 'id=?', whereArgs: [id])).single;
    expect(doc['type'], 'service_invoice');
    expect((doc['vat_total'] as num).toDouble(), 0);
    expect((doc['total'] as num).toDouble(), 1000);

    final revenue = await db.rawQuery(
      "SELECT COALESCE(SUM(credit-debit),0) amount FROM journal_lines "
      "WHERE account_code='4102'");
    expect((revenue.first['amount'] as num).toDouble(), 1000);
  });

  test('Saudi service invoice separates 15 percent VAT', () async {
    await SindarDatabase.instance.saveLicensePolicy(const LicensePolicy(
      customerId: 'SA-SERVICE',
      isTaxEnabled: true,
      countryCode: 'SA',
      currencyCode: 'SAR',
      currencySymbol: 'ر.س',
      maxUsers: 2,
    ));
    final id = await ErpRepository.instance.createServiceInvoice(
      description: 'خدمة تشغيل',
      quantity: 2,
      unitPrice: 500,
      onCredit: false,
      applyTax: true,
    );
    final db = await SindarDatabase.instance.database;
    final doc = (await db.query('documents',
      where: 'id=?', whereArgs: [id])).single;
    expect((doc['subtotal'] as num).toDouble(), 1000);
    expect((doc['vat_total'] as num).toDouble(), 150);
    expect((doc['total'] as num).toDouble(), 1150);

    final lines = await db.rawQuery(
      'SELECT account_code, SUM(debit) debit, SUM(credit) credit '
      'FROM journal_lines GROUP BY account_code');
    final byCode = {for (final line in lines) line['account_code']: line};
    expect((byCode['1101']!['debit'] as num).toDouble(), 1150);
    expect((byCode['4102']!['credit'] as num).toDouble(), 1000);
    expect((byCode['2102']!['credit'] as num).toDouble(), 150);
  });

  test('credit service invoice appears in customer receivables', () async {
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل خدمات');
    await ErpRepository.instance.createServiceInvoice(
      description: 'اشتراك سنوي',
      unitPrice: 2000,
      onCredit: true,
      applyTax: false,
      customerId: customerId,
      customerName: 'عميل خدمات',
    );
    final outstanding = await ErpRepository.instance.outstandingDocuments(
      customerId, receivable: true);
    expect(outstanding, hasLength(1));
    expect(outstanding.single['type'], 'service_invoice');
    expect((outstanding.single['outstanding'] as num).toDouble(), 2000);
  });
}
