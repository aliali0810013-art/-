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
  static const _version = 'SINDAR-LIC-1';

  static String encode({
    required LicenseGrant grant,
    required String signingSecret,
  }) {
    if (signingSecret.length < 16) {
      throw const FormatException('Signing secret is too short');
    }
    final payload = base64UrlEncode(utf8.encode(jsonEncode(grant.toJson())))
        .replaceAll('=', '');
    final signedValue = _version + '.' + payload;
    final signature = Hmac(
      sha256,
      utf8.encode(signingSecret),
    ).convert(utf8.encode(signedValue));
    final sig = base64UrlEncode(signature.bytes).replaceAll('=', '');
    return signedValue + '.' + sig;
  }

  static LicenseGrant decodeAndVerify({
    required String token,
    required String signingSecret,
  }) {
    final parts = token.trim().split('.');
    if (parts.length != 3 || parts[0] != _version) {
      throw const FormatException('Invalid SINDAR license token');
    }
    final signedValue = parts[0] + '.' + parts[1];
    final expected = Hmac(
      sha256,
      utf8.encode(signingSecret),
    ).convert(utf8.encode(signedValue));
    final actual = _decodeUrl(parts[2]);
    if (!_constantTimeEquals(expected.bytes, actual)) {
      throw const FormatException('License signature mismatch');
    }
    final raw = utf8.decode(_decodeUrl(parts[1]));
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid license payload');
    }
    return LicenseGrant.fromJson(decoded);
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
