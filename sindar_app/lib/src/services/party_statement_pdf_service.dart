import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import 'operational_models.dart';

class PartyStatementPdfService {
  const PartyStatementPdfService();

  Future<Uint8List> buildStatement({
    required PartyRecord party,
    required List<StatementRow> rows,
    required LicensePolicy policy,
  }) async {
    final regular = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (_) => [
          _header(
            title: party.type == 'customer' ? 'كشف حساب عميل' : 'كشف حساب مورد',
            number: 'STM-' + party.id.toString().padLeft(6, '0'),
          ),
          pw.SizedBox(height: 16),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  party.name,
                  style: pw.TextStyle(font: bold, fontSize: 16),
                ),
                if (party.commercialRegistration != null)
                  pw.Text(
                    'السجل التجاري: ' + party.commercialRegistration!,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (policy.isTaxEnabled && party.vatNumber != null)
                  pw.Text(
                    'الرقم الضريبي: ' + party.vatNumber!,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                pw.SizedBox(height: 14),
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'التاريخ',
                    'رقم المستند',
                    'نوع العملية',
                    'مدين',
                    'دائن',
                    'الرصيد'
                  ],
                  data: [
                    for (final row in rows)
                      [
                        _date(row.date),
                        row.reference,
                        row.operationType,
                        row.debit.toStringAsFixed(2),
                        row.credit.toStringAsFixed(2),
                        row.balance.toStringAsFixed(2),
                      ],
                  ],
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0A2540)),
                  headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    font: bold,
                    fontSize: 8,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 7.5),
                  cellAlignment: pw.Alignment.center,
                ),
                pw.SizedBox(height: 14),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'الرصيد النهائي: ' +
                        (rows.isEmpty ? '0.00' : rows.last.balance.toStringAsFixed(2)) +
                        ' ' +
                        policy.currencySymbol,
                    style: pw.TextStyle(font: bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> buildClaim({
    required PartyRecord party,
    required List<Map<String, Object?>> invoices,
    required LicensePolicy policy,
  }) async {
    final regular = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final total = invoices.fold<double>(
      0,
      (sum, row) => sum + (row['outstanding'] as num).toDouble(),
    );
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (_) => [
          _header(
            title: 'مطالبة مالية',
            number: 'CLM-' + party.id.toString().padLeft(6, '0'),
          ),
          pw.SizedBox(height: 16),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'السادة / ' + party.name,
                  style: pw.TextStyle(font: bold, fontSize: 15),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'نأمل التكرم بسداد المبالغ المستحقة الموضحة أدناه حسب السجلات المالية.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 14),
                pw.TableHelper.fromTextArray(
                  headers: const ['رقم الفاتورة', 'التاريخ', 'الإجمالي', 'المتبقي'],
                  data: [
                    for (final row in invoices)
                      [
                        row['number']! as String,
                        _date(DateTime.parse(row['date']! as String)),
                        (row['total'] as num).toDouble().toStringAsFixed(2),
                        (row['outstanding'] as num).toDouble().toStringAsFixed(2),
                      ],
                  ],
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0A2540)),
                  headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    font: bold,
                    fontSize: 8,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellAlignment: pw.Alignment.center,
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'إجمالي المبلغ المطالب به: ' +
                      total.toStringAsFixed(2) +
                      ' ' +
                      policy.currencySymbol,
                  style: pw.TextStyle(font: bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _header({required String title, required String number}) {
    final now = DateTime.now();
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'مؤسسة سندار التجارية',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                    color: const PdfColor.fromInt(0xFF0A2540),
                  ),
                ),
                pw.Text('SINDAR Trading Est.',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                  color: const PdfColor.fromInt(0xFFE5A93C),
                ),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('التاريخ: ' + _date(now),
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Text('رقم المستند: ' + number,
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return value.year.toString() +
        '-' +
        two(value.month) +
        '-' +
        two(value.day);
  }
}
