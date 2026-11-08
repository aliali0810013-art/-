import '../licensing/license_policy.dart';

enum DocumentType {
  simplifiedTaxInvoice,
  taxInvoice,
  commercialInvoice,
  quotation,
  receiptVoucher,
  paymentVoucher,
  officialLetter,
  financialClaim,
  customerStatement,
  supplierStatement,
  purchaseInvoice,
  rentalContract,
  payrollVoucher,
}

extension DocumentTypeX on DocumentType {
  bool get isInvoice =>
      this == DocumentType.simplifiedTaxInvoice ||
      this == DocumentType.taxInvoice ||
      this == DocumentType.commercialInvoice;

  bool get isTaxInvoice =>
      this == DocumentType.simplifiedTaxInvoice ||
      this == DocumentType.taxInvoice;

  String get titleAr => switch (this) {
        DocumentType.simplifiedTaxInvoice => 'فاتورة ضريبية مبسطة',
        DocumentType.taxInvoice => 'فاتورة ضريبية',
        DocumentType.commercialInvoice => 'فاتورة مبيعات',
        DocumentType.quotation => 'عرض سعر',
        DocumentType.receiptVoucher => 'سند قبض',
        DocumentType.paymentVoucher => 'سند صرف',
        DocumentType.officialLetter => 'خطاب رسمي',
        DocumentType.financialClaim => 'مطالبة مالية',
        DocumentType.customerStatement => 'كشف حساب عميل',
        DocumentType.supplierStatement => 'كشف حساب مورد',
        DocumentType.purchaseInvoice => 'فاتورة مشتريات',
        DocumentType.rentalContract => 'عقد تأجير معدات',
        DocumentType.payrollVoucher => 'مسير رواتب',
      };
}

enum ContactChannelType {
  mobile,
  phone,
  email,
  website,
}

class ContactChannel {
  const ContactChannel({
    required this.type,
    required this.value,
    this.label,
  });

  final ContactChannelType type;
  final String value;
  final String? label;
}

class CompanyProfile {
  const CompanyProfile({
    required this.nameAr,
    required this.nameEn,
    required this.commercialRegistration,
    this.vatNumber,
  });

  final String nameAr;
  final String nameEn;
  final String commercialRegistration;
  final String? vatNumber;

  CompanyProfile sanitizedFor(LicensePolicy policy) {
    return CompanyProfile(
      nameAr: nameAr,
      nameEn: nameEn,
      commercialRegistration: commercialRegistration,
      vatNumber: policy.taxModeEnabled ? vatNumber : null,
    );
  }
}

class DocumentLine {
  const DocumentLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.vatRate = 0,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double vatRate;

  double get net => quantity * unitPrice;
  double get vat => net * vatRate;
  double get gross => net + vat;

  DocumentLine sanitizedFor(LicensePolicy policy) {
    return DocumentLine(
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      vatRate: policy.taxModeEnabled ? vatRate : 0,
    );
  }
}

class DocumentIdentity {
  const DocumentIdentity({
    this.primaryColorArgb = 0xFF0D2C54,
    this.accentColorArgb = 0xFFE5A93C,
  });

  final int primaryColorArgb;
  final int accentColorArgb;
}

class DocumentDraft {
  const DocumentDraft({
    required this.type,
    required this.number,
    required this.date,
    required this.company,
    required this.lines,
    required this.contacts,
    required this.identity,
    this.partyName,
    this.buyerVatNumber,
    this.buyerCommercialRegistration,
    this.notes,
  });

  final DocumentType type;
  final String number;
  final DateTime date;
  final CompanyProfile company;
  final List<DocumentLine> lines;
  final List<ContactChannel> contacts;
  final DocumentIdentity identity;
  final String? partyName;
  final String? buyerVatNumber;
  final String? buyerCommercialRegistration;
  final String? notes;

  double get netTotal => lines.fold(0, (sum, line) => sum + line.net);
  double get vatTotal => lines.fold(0, (sum, line) => sum + line.vat);
  double get grandTotal => netTotal + vatTotal;

  DocumentDraft sanitizedFor(LicensePolicy policy) {
    final effectiveType = !policy.taxModeEnabled && type.isInvoice
        ? DocumentType.commercialInvoice
        : type;
    return DocumentDraft(
      type: effectiveType,
      number: number,
      date: date,
      company: company.sanitizedFor(policy),
      lines: lines.map((line) => line.sanitizedFor(policy)).toList(growable: false),
      contacts: contacts,
      identity: identity,
      partyName: partyName,
      buyerVatNumber: policy.taxModeEnabled ? buyerVatNumber : null,
      buyerCommercialRegistration:
          policy.taxModeEnabled ? buyerCommercialRegistration : null,
      notes: notes,
    );
  }
}
