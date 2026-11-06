import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  const company = CompanyProfile(
    nameAr: 'سندار',
    nameEn: 'SINDAR',
    commercialRegistration: '1010101010',
    vatNumber: '310123456700003',
  );

  final draft = DocumentDraft(
    type: DocumentType.taxInvoice,
    number: 'INV-1',
    date: DateTime.utc(2026, 11, 7),
    company: company,
    lines: const [
      DocumentLine(description: 'خدمة', quantity: 1, unitPrice: 100, vatRate: .15),
    ],
    contacts: const [],
    identity: const DocumentIdentity(),
    buyerVatNumber: '310999999900003',
  );

  test('tax locked policy strips all VAT fields and turns invoice commercial', () {
    final safe = draft.sanitizedFor(LicensePolicy.lockedDefault);
    expect(safe.type, DocumentType.commercialInvoice);
    expect(safe.company.vatNumber, isNull);
    expect(safe.buyerVatNumber, isNull);
    expect(safe.vatTotal, 0);
    expect(safe.grandTotal, 100);
  });

  test('tax enabled policy keeps VAT fields', () {
    const enabled = LicensePolicy(
      customerId: 'C1',
      isTaxEnabled: true,
      countryCode: 'SA',
      currencyCode: 'SAR',
      currencySymbol: 'ر.س',
      maxUsers: 3,
    );
    final safe = draft.sanitizedFor(enabled);
    expect(safe.type, DocumentType.taxInvoice);
    expect(safe.company.vatNumber, '310123456700003');
    expect(safe.buyerVatNumber, '310999999900003');
    expect(safe.vatTotal, 15);
    expect(safe.grandTotal, 115);
  });
}
