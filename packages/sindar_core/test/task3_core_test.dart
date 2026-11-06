import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('automatic sales posting is balanced', () {
    final journal = AutomaticPosting.sales(
      date: DateTime.utc(2026, 11, 7),
      referenceId: 1,
      net: 100,
      vat: 15,
      onCredit: true,
    );
    expect(journal.isBalanced, isTrue);
    expect(journal.totalDebit, 115);
    expect(journal.totalCredit, 115);
  });

  test('compound journal rejects imbalance', () {
    final journal = JournalDraft(
      date: DateTime.utc(2026, 11, 7),
      description: 'اختبار',
      lines: const [
        JournalLineDraft(accountCode: '1101', debit: 100),
        JournalLineDraft(accountCode: '4101', credit: 90),
      ],
    );
    expect(journal.isBalanced, isFalse);
    expect(journal.validate, throwsFormatException);
  });

  test('license token round-trips and detects tampering', () {
    const secret = 'sindar-offline-signing-key-v1';
    final grant = LicenseGrant(
      organizationName: 'مؤسسة سندار',
      licenseNumber: 'LIC-1001',
      expiresAt: DateTime.utc(2027, 11, 7),
      isActive: true,
      policy: const LicensePolicy(
        customerId: 'C-1001',
        isTaxEnabled: true,
        countryCode: 'SA',
        currencyCode: 'SAR',
        currencySymbol: 'ر.س',
        maxUsers: 5,
      ),
    );
    final token = LicenseTokenCodec.encode(
      grant: grant,
      signingSecret: secret,
    );
    final decoded = LicenseTokenCodec.decodeAndVerify(
      token: token,
      signingSecret: secret,
    );
    expect(decoded.organizationName, 'مؤسسة سندار');
    expect(decoded.policy.maxUsers, 5);
    final tampered = token.substring(0, token.length - 1) + 'x';
    expect(
      () => LicenseTokenCodec.decodeAndVerify(
        token: tampered,
        signingSecret: secret,
      ),
      throwsFormatException,
    );
  });
}
