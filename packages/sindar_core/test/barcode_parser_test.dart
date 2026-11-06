import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('universal parser detects SINDAR commercial invoice', () {
    final raw = CommercialQrCodec.encode(
      CommercialInvoiceQrData(
        sellerName: 'سندار',
        documentNumber: 'INV-10',
        timestamp: DateTime.utc(2026, 11, 7),
        total: 55,
        currencyCode: 'YER',
      ),
    );
    final result = UniversalBarcodeParser.parse(raw);
    expect(result.kind, BarcodePayloadKind.sindarCommercialInvoice);
    expect(result.commercial?.documentNumber, 'INV-10');
  });

  test('universal parser preserves ordinary product barcode', () {
    final result = UniversalBarcodeParser.parse('6281000000012');
    expect(result.kind, BarcodePayloadKind.generic);
    expect(result.rawValue, '6281000000012');
  });
}
