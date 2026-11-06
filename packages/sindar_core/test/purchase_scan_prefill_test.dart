import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('purchase prefill maps ZATCA supplier and totals', () {
    final qr = ZatcaTlvQr.encode(
      ZatcaQrData(
        sellerName: 'مورد الاختبار',
        sellerVatNumber: '310123456700003',
        timestamp: DateTime.utc(2026, 11, 7, 1, 30),
        invoiceTotal: 115,
        vatTotal: 15,
      ),
    );
    final prefill = PurchaseScanPrefill.fromScan(
      UniversalBarcodeParser.parse(qr),
    );
    expect(prefill.supplierName, 'مورد الاختبار');
    expect(prefill.supplierVatNumber, '310123456700003');
    expect(prefill.total, 115);
    expect(prefill.vatTotal, 15);
  });

  test('ordinary item barcode remains a product barcode', () {
    final prefill = PurchaseScanPrefill.fromScan(
      UniversalBarcodeParser.parse('6281000000012'),
    );
    expect(prefill.productBarcode, '6281000000012');
  });
}
