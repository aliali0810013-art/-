import 'dart:convert';
import 'dart:typed_data';

class ZatcaQrData {
  const ZatcaQrData({
    required this.sellerName,
    required this.sellerVatNumber,
    required this.timestamp,
    required this.invoiceTotal,
    required this.vatTotal,
  });

  final String sellerName;
  final String sellerVatNumber;
  final DateTime timestamp;
  final double invoiceTotal;
  final double vatTotal;

  void validate() {
    if (sellerName.trim().isEmpty) {
      throw const FormatException('Seller name is required');
    }
    if (!RegExp(r'^\d{15}$').hasMatch(sellerVatNumber)) {
      throw const FormatException('Seller VAT number must contain exactly 15 digits');
    }
    if (invoiceTotal < 0 || vatTotal < 0 || vatTotal > invoiceTotal) {
      throw const FormatException('Invalid invoice/VAT totals');
    }
  }
}

class ZatcaDecodedQr {
  const ZatcaDecodedQr({
    required this.sellerName,
    required this.sellerVatNumber,
    required this.timestamp,
    required this.invoiceTotal,
    required this.vatTotal,
    required this.rawTags,
  });

  final String sellerName;
  final String sellerVatNumber;
  final DateTime timestamp;
  final double invoiceTotal;
  final double vatTotal;
  final Map<int, Uint8List> rawTags;

  bool get hasPhase2SecurityTags =>
      rawTags.containsKey(6) &&
      rawTags.containsKey(7) &&
      rawTags.containsKey(8);
}

abstract final class ZatcaTlvQr {
  static String encode(ZatcaQrData data) {
    data.validate();
    final bytes = BytesBuilder(copy: false);
    _writeUtf8(bytes, 1, data.sellerName.trim());
    _writeUtf8(bytes, 2, data.sellerVatNumber);
    _writeUtf8(bytes, 3, _formatIsoSeconds(data.timestamp.toUtc()));
    _writeUtf8(bytes, 4, data.invoiceTotal.toStringAsFixed(2));
    _writeUtf8(bytes, 5, data.vatTotal.toStringAsFixed(2));
    return base64.encode(bytes.takeBytes());
  }

  static ZatcaDecodedQr decode(String encoded) {
    final bytes = base64.decode(encoded.trim());
    final tags = <int, Uint8List>{};
    var index = 0;

    while (index < bytes.length) {
      if (index + 2 > bytes.length) {
        throw const FormatException('Incomplete TLV header');
      }
      final tag = bytes[index++];
      final length = bytes[index++];
      if (index + length > bytes.length) {
        throw const FormatException('TLV length exceeds available data');
      }
      tags[tag] = Uint8List.fromList(bytes.sublist(index, index + length));
      index += length;
    }

    for (var tag = 1; tag <= 5; tag++) {
      if (!tags.containsKey(tag)) {
        throw FormatException('Missing required ZATCA tag $tag');
      }
    }

    String text(int tag) => utf8.decode(tags[tag]!, allowMalformed: false);

    final timestamp = DateTime.tryParse(text(3));
    final invoiceTotal = double.tryParse(text(4));
    final vatTotal = double.tryParse(text(5));
    if (timestamp == null || invoiceTotal == null || vatTotal == null) {
      throw const FormatException('Invalid ZATCA QR values');
    }

    return ZatcaDecodedQr(
      sellerName: text(1),
      sellerVatNumber: text(2),
      timestamp: timestamp,
      invoiceTotal: invoiceTotal,
      vatTotal: vatTotal,
      rawTags: Map.unmodifiable(tags),
    );
  }

  static bool canDecode(String value) {
    try {
      decode(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static void _writeUtf8(BytesBuilder output, int tag, String value) {
    final valueBytes = utf8.encode(value);
    if (valueBytes.length > 255) {
      throw FormatException('ZATCA TLV value for tag $tag exceeds 255 UTF-8 bytes');
    }
    output.addByte(tag);
    output.addByte(valueBytes.length);
    output.add(valueBytes);
  }

  static String _formatIsoSeconds(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }
}
