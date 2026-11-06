import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

class DocumentPdfService {
  const DocumentPdfService();

  Future<Uint8List> build({
    required DocumentDraft draft,
    required LicensePolicy policy,
    Uint8List? logoBytes,
  }) async {
    final safe = draft.sanitizedFor(policy);
    final regular = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final primary = _color(safe.identity.primaryColorArgb);
    final accent = _color(safe.identity.accentColorArgb);
    final document = pw.Document();

    final qrData = safe.type.isInvoice ? _invoiceQr(safe, policy) : null;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 34),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _header(
                  safe,
                  policy,
                  primary,
                  accent,
                  qrData,
                  logoBytes,
                ),
                pw.SizedBox(height: 18),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 9),
                  decoration: pw.BoxDecoration(
                    color: primary,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      safe.type.titleAr,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        font: bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 14),
                if (safe.partyName != null || safe.buyerVatNumber != null)
                  _partyBlock(safe, policy, primary),
                if (safe.partyName != null || safe.buyerVatNumber != null)
                  pw.SizedBox(height: 12),
                _linesTable(safe, primary, accent),
                pw.SizedBox(height: 12),
                _totals(safe, policy, primary, bold),
                if (safe.type == DocumentType.receiptVoucher ||
                    safe.type == DocumentType.paymentVoucher) ...[
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: primary),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'المبلغ كتابة: ${ArabicAmountInWords.spell(safe.grandTotal, currencyName: _currencyName(policy.currencyCode))}',
                      style: pw.TextStyle(font: bold, fontSize: 11),
                    ),
                  ),
                ],
                if (safe.notes?.trim().isNotEmpty == true) ...[
                  pw.SizedBox(height: 12),
                  pw.Text('ملاحظات: ${safe.notes}', style: const pw.TextStyle(fontSize: 10)),
                ],
                pw.SizedBox(height: 22),
                _signatureArea(primary),
              ],
            ),
          ),
        ],
        footer: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: _footer(safe.contacts, primary, accent),
        ),
      ),
    );

    return document.save();
  }

  pw.Widget _header(
    DocumentDraft draft,
    LicensePolicy policy,
    PdfColor primary,
    PdfColor accent,
    String? qrData,
    Uint8List? logoBytes,
  ) {
    final company = draft.company;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                company.nameAr,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                  color: primary,
                ),
              ),
              pw.Text(company.nameEn, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 3),
              pw.Text(
                'السجل التجاري: ${company.commercialRegistration}',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
              if (policy.isTaxEnabled && company.vatNumber != null)
                pw.Text(
                  'الرقم الضريبي: ${company.vatNumber}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          width: 120,
          alignment: pw.Alignment.topCenter,
          child: logoBytes != null
              ? pw.Image(pw.MemoryImage(logoBytes), height: 58, fit: pw.BoxFit.contain)
              : pw.Column(
                  children: [
                    pw.Text(
                      'سندار',
                      style: pw.TextStyle(
                        fontSize: 23,
                        fontWeight: pw.FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    pw.Text('SINDAR', style: pw.TextStyle(fontSize: 10, color: accent)),
                  ],
                ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: draft.type.isInvoice
              ? pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (qrData != null)
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: qrData,
                        width: 72,
                        height: 72,
                        drawText: false,
                      ),
                    pw.SizedBox(height: 3),
                    pw.Text(_date(draft.date), style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(draft.number, style: const pw.TextStyle(fontSize: 8)),
                  ],
                )
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('التاريخ', style: pw.TextStyle(fontSize: 8, color: primary)),
                    pw.Text(_date(draft.date), style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 8),
                    pw.Text('رقم المستند', style: pw.TextStyle(fontSize: 8, color: primary)),
                    pw.Text(draft.number, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
        ),
      ],
    );
  }

  pw.Widget _partyBlock(DocumentDraft draft, LicensePolicy policy, PdfColor primary) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor(primary.red, primary.green, primary.blue, .05),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor(primary.red, primary.green, primary.blue, .2)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text('العميل/الجهة: ${draft.partyName ?? '-'}')),
          if (policy.isTaxEnabled && draft.buyerVatNumber != null)
            pw.Expanded(
              child: pw.Text(
                'الرقم الضريبي للعميل: ${draft.buyerVatNumber}',
                textAlign: pw.TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _linesTable(DocumentDraft draft, PdfColor primary, PdfColor accent) {
    final data = <List<Object>>[
      for (var i = 0; i < draft.lines.length; i++)
        [
          i + 1,
          draft.lines[i].description,
          draft.lines[i].quantity.toStringAsFixed(2),
          draft.lines[i].unitPrice.toStringAsFixed(2),
          draft.lines[i].vatRate == 0 ? '-' : '${(draft.lines[i].vatRate * 100).toStringAsFixed(0)}%',
          draft.lines[i].gross.toStringAsFixed(2),
        ],
    ];

    return pw.TableHelper.fromTextArray(
      headers: const ['#', 'البيان', 'الكمية', 'السعر', 'الضريبة', 'الإجمالي'],
      data: data,
      headerDecoration: pw.BoxDecoration(color: primary),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      border: pw.TableBorder.all(color: PdfColor(accent.red, accent.green, accent.blue, .45), width: .5),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    );
  }

  pw.Widget _totals(
    DocumentDraft draft,
    LicensePolicy policy,
    PdfColor primary,
    pw.Font bold,
  ) {
    final symbol = policy.currencySymbol;
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        width: 230,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: primary, width: .8),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            _totalRow('الإجمالي قبل الضريبة', draft.netTotal, symbol),
            if (policy.isTaxEnabled)
              _totalRow('ضريبة القيمة المضافة', draft.vatTotal, symbol),
            pw.Divider(color: primary),
            _totalRow('الإجمالي النهائي', draft.grandTotal, symbol, font: bold),
          ],
        ),
      ),
    );
  }

  pw.Widget _totalRow(String label, double value, String symbol, {pw.Font? font}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9))),
          pw.Text('${value.toStringAsFixed(2)} $symbol', style: pw.TextStyle(font: font, fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _signatureArea(PdfColor primary) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _signatureBox('المستلم', primary),
        _signatureBox('المحاسب', primary),
        _signatureBox('الختم والتوقيع', primary),
      ],
    );
  }

  pw.Widget _signatureBox(String label, PdfColor primary) {
    return pw.Container(
      width: 145,
      height: 55,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor(primary.red, primary.green, primary.blue, .35)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  pw.Widget _footer(List<ContactChannel> contacts, PdfColor primary, PdfColor accent) {
    if (contacts.isEmpty) return pw.SizedBox();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColor(primary.red, primary.green, primary.blue, .06),
        border: pw.Border(top: pw.BorderSide(color: accent, width: 1.2)),
      ),
      child: pw.Wrap(
        alignment: pw.WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final item in contacts)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor(primary.red, primary.green, primary.blue, .18)),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                '${_contactLabel(item.type)}: ${item.value}',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ),
        ],
      ),
    );
  }

  String _invoiceQr(DocumentDraft draft, LicensePolicy policy) {
    if (policy.isTaxEnabled && draft.type.isTaxInvoice) {
      final vat = draft.company.vatNumber;
      if (vat == null || vat.isEmpty) {
        throw StateError('Tax mode requires a seller VAT number before generating a tax invoice');
      }
      return ZatcaTlvQr.encode(
        ZatcaQrData(
          sellerName: draft.company.nameAr,
          sellerVatNumber: vat,
          timestamp: draft.date,
          invoiceTotal: draft.grandTotal,
          vatTotal: draft.vatTotal,
        ),
      );
    }

    return CommercialQrCodec.encode(
      CommercialInvoiceQrData(
        sellerName: draft.company.nameAr,
        documentNumber: draft.number,
        timestamp: draft.date,
        total: draft.grandTotal,
        currencyCode: policy.currencyCode,
      ),
    );
  }

  PdfColor _color(int argb) {
    return PdfColor(
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
    );
  }

  String _date(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _contactLabel(ContactChannelType type) => switch (type) {
        ContactChannelType.mobile => 'جوال',
        ContactChannelType.phone => 'هاتف',
        ContactChannelType.email => 'بريد',
        ContactChannelType.website => 'موقع',
      };

  String _currencyName(String code) => switch (code) {
        'SAR' => 'ريال',
        'YER' => 'ريال',
        'USD' => 'دولار',
        _ => code,
      };
}
