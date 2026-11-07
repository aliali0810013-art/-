import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import 'package:sindar_app/src/data/local/sindar_database.dart';
import 'package:sindar_app/src/screens/equipment_rental_screen.dart';
import 'package:sindar_app/src/services/erp_repository.dart';
import 'package:sindar_app/src/services/rental_accrual_service.dart';
import 'package:sindar_app/src/services/rental_pricing.dart';

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
    return const EquipmentRentalService().addEquipment(
      code: 'RENT-001', name: 'مضخة مياه', dailyRate: 500,
      hourlyRate: 50, weeklyRate: 300, monthlyRate: 1100,
      yearlyRate: 10000, purchasePrice: 2500, salePrice: 3500,
    );
  }

  test('hourly lease, deferred income, accrual, receipt and no duplicate entry', () async {
    final customerId = await ErpRepository.instance.addParty(
      type: 'customer', name: 'عميل معدات');
    final equipmentId = await createHourlyEquipment();
    final start = DateTime.utc(2026, 1, 15, 10);
    final docId = await const EquipmentRentalService().rent(
      equipmentId: equipmentId, customerId: customerId,
      start: start, period: RentalPeriod.hour, quantity: 4);
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

    expect(await balance('2106'), 200); // liability, no income yet
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
    final paid = (await db.query('documents', where: 'id=?',
      whereArgs: [docId])).single['paid_amount'] as num;
    expect(paid.toDouble(), 75);
    await expectLater(ErpRepository.instance.createVoucher(
      receipt: true, amount: 126, partyId: customerId,
      linkedDocumentId: docId), throwsFormatException);

    await const RentalAccrualService().accrue(
      asOf: start.add(const Duration(hours: 4)));
    expect(await balance('2106'), closeTo(0, 0.01));
    expect(await balance('4104'), 200);
    expect(await balance('1101'), 75);
  });

  test('catalog purchase and sale price edits affect future selection', () async {
    final itemId = await ErpRepository.instance.addItem(
      code: 'SKU-RENT', name: 'مولد صغير', purchasePrice: 100,
      salePrice: 200, quantity: 4);
    await ErpRepository.instance.updateItemPrices(
      itemId: itemId, purchasePrice: 130, salePrice: 230);
    final item = (await ErpRepository.instance.listItems()).single;
    expect(item.purchasePrice, 130);
    expect(item.salePrice, 230);
    final equipmentId = await const EquipmentRentalService().addEquipment(
      code: item.code, name: item.name, catalogItemId: item.id,
      purchasePrice: item.purchasePrice, salePrice: item.salePrice,
      hourlyRate: 10, dailyRate: 50, weeklyRate: 300,
      monthlyRate: 800, yearlyRate: 8000);
    final db = await SindarDatabase.instance.database;
    final equipment = (await db.query('rental_equipment', where: 'id=?',
      whereArgs: [equipmentId])).single;
    expect(equipment['catalog_item_id'], itemId);
    expect((equipment['purchase_price'] as num).toDouble(), 130);
    // Catalog reference must never quietly decrement merchandise stock.
    expect((await ErpRepository.instance.listItems()).single.quantity, 4);
  });
}
