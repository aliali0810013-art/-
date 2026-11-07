import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'sindar-offline-signing-key-v1';

  test('license token round trips owner restrictions', () {
    final grant = LicenseGrant(
      organizationName: 'مؤسسة الاختبار',
      licenseNumber: 'LIC-9001',
      expiresAt: DateTime.utc(2030, 1, 1),
      isActive: true,
      policy: const LicensePolicy(
        customerId: 'LIC-9001',
        isTaxEnabled: true,
        countryCode: 'SA',
        currencyCode: 'SAR',
        currencySymbol: 'ر.س',
        maxUsers: 7,
      ),
    );

    final token = LicenseTokenCodec.encode(
      grant: grant,
      signingSecret: secret,
    );
    expect(token.startsWith('S2.'), isTrue);
    expect(token.length, lessThan(160));

    final decoded = LicenseTokenCodec.decodeAndVerify(
      token: token,
      signingSecret: secret,
    );

    expect(decoded.organizationName, 'مؤسسة الاختبار');
    expect(decoded.licenseNumber, 'LIC-9001');
    expect(decoded.policy.isTaxEnabled, isTrue);
    expect(decoded.policy.maxUsers, 7);
    expect(decoded.policy.currencyCode, 'SAR');
  });

  test('license token detects tampering', () {
    final grant = LicenseGrant(
      organizationName: 'SINDAR',
      licenseNumber: 'LIC-1',
      expiresAt: DateTime.utc(2030),
      isActive: true,
      policy: const LicensePolicy(
        customerId: 'LIC-1',
        isTaxEnabled: false,
        countryCode: 'YE',
        currencyCode: 'YER',
        currencySymbol: 'ر.ي',
        maxUsers: 2,
      ),
    );
    final token = LicenseTokenCodec.encode(
      grant: grant,
      signingSecret: secret,
    );
    final replacement = token.endsWith('A') ? 'B' : 'A';
    final tampered = token.substring(0, token.length - 1) + replacement;

    expect(
      () => LicenseTokenCodec.decodeAndVerify(
        token: tampered,
        signingSecret: secret,
      ),
      throwsFormatException,
    );
  });
}
