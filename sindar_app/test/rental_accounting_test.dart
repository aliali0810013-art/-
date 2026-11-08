import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sindar_core/sindar_core.dart';

import 'package:sindar_app/src/data/local/sindar_database.dart';
import 'package:sindar_app/src/services/equipment_catalog_service.dart';
import 'package:sindar_app/src/services/erp_repository.dart';
import 'package:sindar_app/src/services/rental_accrual_service.dart';
import 'package:sindar_app/src/services/rental_pricing.dart';
import 'package:sindar_app/src/services/rental_workflow_service.dart';

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

  Future<int> createHourlyEquipment() {
    return const EquipmentCatalogService().add(
      code: 'RENT-001',
      name: 'مضخة مياه',
      dailyRate: 500,
      hourlyRate: 50,
      weeklyRate: 300,
      monthlyRate: 1100,
      yearlyRate: 10000,
      purchaseCost: 2500,
      marketValue: 3500,
    );
  }

  test('custom hourly lease, deferred income, accrual and linked receipt', () async {
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل معدات');
    final equipmentId = await createHourlyEquipment();
    final start = DateTime.utc(2026, 1, 15, 10);
    final docId = await const RentalWorkflowService().createRental(
      equipmentId: equipmentId,
      customerId: customerId,
      start: start,
      period: RentalPeriod.hour,
      quantity: 4,
      agreedRate: 50,
      taxInvoice: false,
    );
    final db = await SindarDatabase.instance.database;

    final invoice = (await db.query('documents',
      where: 'id=?', whereArgs: [docId])).single;
    expect(invoice['type'], 'equipment_rental');
    expect((invoice['total'] as num).toDouble(), 200);

    Future<double> balance(String account) async {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(credit-debit),0) amount '
        'FROM journal_lines WHERE account_code=?', [account]);
      return (rows.first['amount'] as num).toDouble();
    }

    expect(await balance('2106'), 200);
    expect(await balance('4104'), 0);

    await const RentalAccrualService().accrue(
      asOf: start.add(const Duration(hours: 2)));
    expect(await balance('2106'), 100);
    expect(await balance('4104'), 100);

    final beforeRepeat = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM journal_entries "
      "WHERE reference_type='equipment_rental_accrual'"))!;
    await const RentalAccrualService().accrue(
      asOf: start.add(const Duration(hours: 2)));
    final afterRepeat = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM journal_entries "
      "WHERE reference_type='equipment_rental_accrual'"))!;
    expect(afterRepeat, beforeRepeat);

    final otherCustomer = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل آخر');
    await expectLater(
      ErpRepository.instance.createVoucher(
        receipt: true, amount: 20, partyId: otherCustomer,
        linkedDocumentId: docId), throwsFormatException);
    final receiptId = await ErpRepository.instance.createVoucher(
      receipt: true, amount: 75, partyId: customerId,
      linkedDocumentId: docId);
    expect(receiptId, greaterThan(0));

    await const RentalAccrualService().accrue(
      asOf: start.add(const Duration(hours: 4)));
    expect(await balance('2106'), closeTo(0, 0.01));
    expect(await balance('4104'), 200);
    expect(-await balance('1101'), 75);
  });

  test('agreed rental rate is independent from equipment reference price', () async {
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل سعر خاص');
    final equipmentId = await createHourlyEquipment();
    final docId = await const RentalWorkflowService().createRental(
      equipmentId: equipmentId,
      customerId: customerId,
      start: DateTime.utc(2026, 2, 1),
      period: RentalPeriod.day,
      quantity: 2,
      agreedRate: 2000,
      taxInvoice: false,
    );
    final db = await SindarDatabase.instance.database;
    final rental = (await db.query('equipment_rentals',
      where: 'document_id=?', whereArgs: [docId])).single;
    expect((rental['billing_rate'] as num).toDouble(), 2000);
    final document = (await db.query('documents',
      where: 'id=?', whereArgs: [docId])).single;
    expect((document['total'] as num).toDouble(), 4000);
  });

  test('rental quotation posts no journal and converts once to contract', () async {
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل عرض');
    final equipmentId = await createHourlyEquipment();
    final quoteId = await const RentalWorkflowService().createQuote(
      equipmentId: equipmentId,
      customerId: customerId,
      start: DateTime.utc(2026, 3, 1),
      period: RentalPeriod.week,
      quantity: 2,
      agreedRate: 900,
      taxInvoice: false,
    );
    final db = await SindarDatabase.instance.database;
    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM journal_entries'))!;
    expect(before, 0);
    final contractId =
        await const RentalWorkflowService().convertQuote(quoteId);
    expect(contractId, greaterThan(0));
    final after = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM journal_entries'))!;
    expect(after, 1);
    await expectLater(
      const RentalWorkflowService().convertQuote(quoteId),
      throwsFormatException,
    );
  });

  test('Yemen hides tax even if malformed license flag says enabled', () async {
    await SindarDatabase.instance.saveLicensePolicy(const LicensePolicy(
      customerId: 'YE-TEST',
      isTaxEnabled: true,
      countryCode: 'YE',
      currencyCode: 'YER',
      currencySymbol: 'ر.ي',
      maxUsers: 2,
    ));
    final policy = await SindarDatabase.instance.getLicensePolicy();
    expect(policy.taxModeEnabled, isFalse);
    expect(policy.currencyNameAr, 'ريال يمني');

    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل يمني');
    final equipmentId = await createHourlyEquipment();
    final docId = await const RentalWorkflowService().createRental(
      equipmentId: equipmentId,
      customerId: customerId,
      start: DateTime.utc(2026, 4, 1),
      period: RentalPeriod.day,
      quantity: 1,
      agreedRate: 1000,
      taxInvoice: true,
    );
    final db = await SindarDatabase.instance.database;
    final doc = (await db.query('documents',
      where: 'id=?', whereArgs: [docId])).single;
    expect((doc['vat_total'] as num).toDouble(), 0);
    expect((doc['total'] as num).toDouble(), 1000);
  });

  test('Saudi taxable rental separates VAT from deferred rental revenue', () async {
    await SindarDatabase.instance.saveLicensePolicy(const LicensePolicy(
      customerId: 'SA-TEST',
      isTaxEnabled: true,
      countryCode: 'SA',
      currencyCode: 'SAR',
      currencySymbol: 'ر.س',
      maxUsers: 2,
    ));
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل سعودي');
    final equipmentId = await createHourlyEquipment();
    final docId = await const RentalWorkflowService().createRental(
      equipmentId: equipmentId,
      customerId: customerId,
      start: DateTime.utc(2026, 5, 1),
      period: RentalPeriod.day,
      quantity: 1,
      agreedRate: 1000,
      taxInvoice: true,
    );
    final db = await SindarDatabase.instance.database;
    final doc = (await db.query('documents',
      where: 'id=?', whereArgs: [docId])).single;
    expect((doc['subtotal'] as num).toDouble(), 1000);
    expect((doc['vat_total'] as num).toDouble(), 150);
    expect((doc['total'] as num).toDouble(), 1150);

    Future<double> credit(String account) async {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(credit),0) amount '
        'FROM journal_lines WHERE account_code=?', [account]);
      return (rows.first['amount'] as num).toDouble();
    }
    expect(await credit('2106'), 1000);
    expect(await credit('2102'), 150);
  });

  test('equipment catalog is independent from merchandise stock', () async {
    final itemId = await ErpRepository.instance.addItem(
      code: 'SKU-001', name: 'صنف مخزني', purchasePrice: 100,
      salePrice: 200, quantity: 4);
    await ErpRepository.instance.updateItemPrices(
      itemId: itemId, purchasePrice: 130, salePrice: 230);
    await const EquipmentCatalogService().add(
      code: 'EQ-001', name: 'مولد مستقل', purchaseCost: 2500,
      marketValue: 3000, hourlyRate: 20);
    final item = (await ErpRepository.instance.listItems()).single;
    expect(item.quantity, 4);
    expect(item.purchasePrice, 130);
    expect(item.salePrice, 230);
  });
}
