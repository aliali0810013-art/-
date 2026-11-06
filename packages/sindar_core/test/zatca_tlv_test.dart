import 'dart:convert';

import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('ZATCA TLV encodes tags 1-5 using UTF-8 byte lengths', () {
    final encoded = ZatcaTlvQr.encode(
      ZatcaQrData(
        sellerName: 'مؤسسة سندار',
        sellerVatNumber: '310123456700003',
        timestamp: DateTime.utc(2026, 11, 7, 1, 30, 45),
        invoiceTotal: 115.00,
        vatTotal: 15.00,
      ),
    );

    final bytes = base64.decode(encoded);
    expect(bytes.first, 1);
    final sellerBytes = utf8.encode('مؤسسة سندار');
    expect(bytes[1], sellerBytes.length);

    final decoded = ZatcaTlvQr.decode(encoded);
    expect(decoded.sellerName, 'مؤسسة سندار');
    expect(decoded.sellerVatNumber, '310123456700003');
    expect(decoded.timestamp, DateTime.utc(2026, 11, 7, 1, 30, 45));
    expect(decoded.invoiceTotal, 115.00);
    expect(decoded.vatTotal, 15.00);
    expect(decoded.hasPhase2SecurityTags, isFalse);
  });

  test('ZATCA encoder rejects invalid seller VAT number', () {
    expect(
      () => ZatcaTlvQr.encode(
        ZatcaQrData(
          sellerName: 'SINDAR',
          sellerVatNumber: '123',
          timestamp: DateTime.utc(2026),
          invoiceTotal: 100,
          vatTotal: 15,
        ),
      ),
      throwsFormatException,
    );
  });
}
