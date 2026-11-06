import 'dart:convert';

import '../tax/zatca_tlv_qr.dart';

enum BarcodePayloadKind {
  zatcaTaxInvoice,
  sindarCommercialInvoice,
  generic,
}

class CommercialInvoiceQrData {
  const CommercialInvoiceQrData({
    required this.sellerName,
    required this.documentNumber,
    required this.timestamp,
    required this.total,
    required this.currencyCode,
  });

  final String sellerName;
  final String documentNumber;
  final DateTime timestamp;
  final double total;
  final String currencyCode;

  Map<String, Object?> toJson() => {
        'seller': sellerName,
        'number': documentNumber,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'total': total,
        'currency': currencyCode,
      };

  factory CommercialInvoiceQrData.fromJson(Map<String, Object?> json) {
    return CommercialInvoiceQrData(
      sellerName: json['seller']! as String,
      documentNumber: json['number']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String),
      total: (json['total']! as num).toDouble(),
      currencyCode: json['currency']! as String,
    );
  }
}

abstract final class CommercialQrCodec {
  static const prefix = 'SINDAR-COMMERCIAL:1:';

  static String encode(CommercialInvoiceQrData data) {
    final payload = utf8.encode(jsonEncode(data.toJson()));
    return '$prefix${base64UrlEncode(payload)}';
  }

  static CommercialInvoiceQrData decode(String value) {
    if (!value.startsWith(prefix)) {
      throw const FormatException('Not a SINDAR commercial invoice QR');
    }
    final encoded = value.substring(prefix.length);
    final json = jsonDecode(utf8.decode(base64Url.decode(encoded)));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid commercial QR payload');
    }
    return CommercialInvoiceQrData.fromJson(json);
  }
}

class UniversalBarcodeResult {
  const UniversalBarcodeResult({
    required this.kind,
    required this.rawValue,
    this.zatca,
    this.commercial,
  });

  final BarcodePayloadKind kind;
  final String rawValue;
  final ZatcaDecodedQr? zatca;
  final CommercialInvoiceQrData? commercial;
}

abstract final class UniversalBarcodeParser {
  static UniversalBarcodeResult parse(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      throw const FormatException('Barcode is empty');
    }

    if (value.startsWith(CommercialQrCodec.prefix)) {
      return UniversalBarcodeResult(
        kind: BarcodePayloadKind.sindarCommercialInvoice,
        rawValue: value,
        commercial: CommercialQrCodec.decode(value),
      );
    }

    try {
      final decoded = ZatcaTlvQr.decode(value);
      return UniversalBarcodeResult(
        kind: BarcodePayloadKind.zatcaTaxInvoice,
        rawValue: value,
        zatca: decoded,
      );
    } on FormatException {
      return UniversalBarcodeResult(
        kind: BarcodePayloadKind.generic,
        rawValue: value,
      );
    }
  }
}

class PurchaseScanPrefill {
  const PurchaseScanPrefill({
    this.supplierName,
    this.supplierVatNumber,
    this.invoiceDate,
    this.total,
    this.vatTotal,
    this.productBarcode,
    this.commercialDocumentNumber,
  });

  final String? supplierName;
  final String? supplierVatNumber;
  final DateTime? invoiceDate;
  final double? total;
  final double? vatTotal;
  final String? productBarcode;
  final String? commercialDocumentNumber;

  factory PurchaseScanPrefill.fromScan(UniversalBarcodeResult result) {
    final zatca = result.zatca;
    if (zatca != null) {
      return PurchaseScanPrefill(
        supplierName: zatca.sellerName,
        supplierVatNumber: zatca.sellerVatNumber,
        invoiceDate: zatca.timestamp,
        total: zatca.invoiceTotal,
        vatTotal: zatca.vatTotal,
      );
    }

    final commercial = result.commercial;
    if (commercial != null) {
      return PurchaseScanPrefill(
        supplierName: commercial.sellerName,
        invoiceDate: commercial.timestamp,
        total: commercial.total,
        commercialDocumentNumber: commercial.documentNumber,
      );
    }

    return PurchaseScanPrefill(productBarcode: result.rawValue);
  }
}
