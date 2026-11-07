import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'license_policy.dart';

class LicenseGrant {
  const LicenseGrant({
    required this.organizationName,
    required this.licenseNumber,
    required this.expiresAt,
    required this.isActive,
    required this.policy,
  });

  final String organizationName;
  final String licenseNumber;
  final DateTime expiresAt;
  final bool isActive;
  final LicensePolicy policy;

  bool get isExpired => expiresAt.isBefore(DateTime.now().toUtc());
  bool get canOperate => isActive && !isExpired;

  Map<String, Object?> toJson() => {
        'organizationName': organizationName,
        'licenseNumber': licenseNumber,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'isActive': isActive,
        'policy': policy.toJson(),
      };

  factory LicenseGrant.fromJson(Map<String, Object?> json) {
    final policyJson = json['policy'];
    if (policyJson is! Map<String, dynamic>) {
      throw const FormatException('Invalid license policy');
    }
    return LicenseGrant(
      organizationName: json['organizationName']! as String,
      licenseNumber: json['licenseNumber']! as String,
      expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
      isActive: json['isActive'] == true,
      policy: LicensePolicy.fromJson(policyJson),
    );
  }
}

abstract final class LicenseTokenCodec {
  static const _legacyVersion = 'SINDAR-LIC-1';
  static const _compactVersion = 'S2';

  static String encode({
    required LicenseGrant grant,
    required String signingSecret,
  }) {
    if (signingSecret.length < 16) {
      throw const FormatException('Signing secret is too short');
    }

    final activeAndTax =
        (grant.isActive ? 1 : 0) | (grant.policy.isTaxEnabled ? 2 : 0);
    final expiresSeconds =
        grant.expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000;

    final fields = <String>[
      _compactVersion,
      _encodeText(grant.organizationName.trim()),
      _encodeText(grant.licenseNumber.trim()),
      expiresSeconds.toRadixString(36),
      activeAndTax.toRadixString(36),
      grant.policy.countryCode.trim().toUpperCase(),
      grant.policy.currencyCode.trim().toUpperCase(),
      _encodeText(grant.policy.currencySymbol.trim()),
      grant.policy.maxUsers.toRadixString(36),
    ];

    final signedValue = fields.join('.');
    final fullSignature = Hmac(
      sha256,
      utf8.encode(signingSecret),
    ).convert(utf8.encode(signedValue));
    final shortSignature = fullSignature.bytes.take(16).toList(growable: false);
    final sig = base64UrlEncode(shortSignature).replaceAll('=', '');
    return signedValue + '.' + sig;
  }

  static LicenseGrant decodeAndVerify({
    required String token,
    required String signingSecret,
  }) {
    final normalized = token.trim();
    if (normalized.startsWith(_compactVersion + '.')) {
      return _decodeCompact(
        token: normalized,
        signingSecret: signingSecret,
      );
    }
    return _decodeLegacy(
      token: normalized,
      signingSecret: signingSecret,
    );
  }

  static LicenseGrant _decodeCompact({
    required String token,
    required String signingSecret,
  }) {
    final parts = token.split('.');
    if (parts.length != 10 || parts[0] != _compactVersion) {
      throw const FormatException('رقم ترخيص سندار غير صالح');
    }

    final signedValue = parts.take(9).join('.');
    final expected = Hmac(
      sha256,
      utf8.encode(signingSecret),
    ).convert(utf8.encode(signedValue)).bytes.take(16).toList(growable: false);
    final actual = _decodeUrl(parts[9]);
    if (!_constantTimeEquals(expected, actual)) {
      throw const FormatException('توقيع رقم الترخيص غير صحيح');
    }

    final expiresSeconds = int.tryParse(parts[3], radix: 36);
    final flags = int.tryParse(parts[4], radix: 36);
    final maxUsers = int.tryParse(parts[8], radix: 36);
    if (expiresSeconds == null ||
        flags == null ||
        maxUsers == null ||
        maxUsers < 1) {
      throw const FormatException('بيانات رقم الترخيص غير صالحة');
    }

    final licenseNumber = _decodeText(parts[2]);
    return LicenseGrant(
      organizationName: _decodeText(parts[1]),
      licenseNumber: licenseNumber,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresSeconds * 1000,
        isUtc: true,
      ),
      isActive: (flags & 1) != 0,
      policy: LicensePolicy(
        customerId: licenseNumber,
        isTaxEnabled: (flags & 2) != 0,
        countryCode: parts[5],
        currencyCode: parts[6],
        currencySymbol: _decodeText(parts[7]),
        maxUsers: maxUsers,
      ),
    );
  }

  static LicenseGrant _decodeLegacy({
    required String token,
    required String signingSecret,
  }) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _legacyVersion) {
      throw const FormatException('رقم ترخيص سندار غير صالح');
    }
    final signedValue = parts[0] + '.' + parts[1];
    final expected = Hmac(
      sha256,
      utf8.encode(signingSecret),
    ).convert(utf8.encode(signedValue));
    final actual = _decodeUrl(parts[2]);
    if (!_constantTimeEquals(expected.bytes, actual)) {
      throw const FormatException('توقيع رقم الترخيص غير صحيح');
    }
    final raw = utf8.decode(_decodeUrl(parts[1]));
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('بيانات رقم الترخيص غير صالحة');
    }
    return LicenseGrant.fromJson(decoded);
  }

  static String _encodeText(String value) {
    return base64UrlEncode(utf8.encode(value)).replaceAll('=', '');
  }

  static String _decodeText(String value) {
    return utf8.decode(_decodeUrl(value));
  }

  static List<int> _decodeUrl(String input) {
    final normalized = input.padRight(
      input.length + ((4 - input.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
