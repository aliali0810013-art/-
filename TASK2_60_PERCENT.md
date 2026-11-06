# SINDAR — Task 2 / cumulative 60%

Implemented on `sindar-phase1`:

- ZATCA TLV Base64 encoder/decoder for standard Tags 1–5 using UTF-8 byte lengths.
- Decoder preserves additional binary TLV tags, so QR payloads containing later security tags can still be scanned.
- Buyer VAT is stored/displayed on B2B invoice data but is not inserted into non-standard QR tags.
- Shared `LicensePolicy.isTaxEnabled` gate. When locked, VAT fields are removed and tax invoices are converted to commercial invoices.
- Country/currency policy model and owner-admin tax/currency control UI.
- Universal camera scanner for ZATCA QR, SINDAR commercial QR, QR and 1D item barcodes.
- Purchase scan prefill mapping for supplier, VAT number, invoice total and VAT total.
- Interactive document studio with editable rows, identity color presets, dynamic footer contacts, QR scanning, PDF preview/print and PDF sharing.
- Conditional document header: QR only on invoices; date + document number on non-invoice documents.
- Receipt/payment-voucher amount spelling in Arabic.
- Commercial QR format for non-tax invoices.
- Android camera and internet permissions injected by CI after `flutter create`.

Regulatory boundary: this task implements the requested ZATCA TLV Tags 1–5. Full Phase-2 FATOORA onboarding, XML signing, CSID, clearance/reporting and cryptographic QR Tags 6–9 require the taxpayer's ZATCA integration credentials and are a separate compliance layer; the decoder preserves those tags when encountered.
