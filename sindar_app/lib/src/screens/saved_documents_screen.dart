import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/session_controller.dart';

/// Reopens genuine saved SQLite documents and posted journal entries.
class SavedDocumentsScreen extends StatefulWidget {
  const SavedDocumentsScreen({super.key});

  @override
  State<SavedDocumentsScreen> createState() => _SavedDocumentsScreenState();
}

class _SavedDocumentsScreenState extends State<SavedDocumentsScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final docs = await ErpRepository.instance.listSavedDocuments();
      final journals = await ErpRepository.instance.listSavedJournalEntries();
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final row in docs) {...row, '_journal': false},
          for (final row in journals)
            {
              'id': row['id'],
              'type': 'journal_entry',
              'number': 'JRN-${(row['id'] as int).toString().padLeft(6, '0')}',
              'date': row['date'],
              'party_name': row['description'],
              '_journal': true,
            },
        ]..sort((a, b) {
            final byDate = (b['date'] as String).compareTo(a['date'] as String);
            return byDate != 0 ? byDate : (b['id'] as int).compareTo(a['id'] as int);
          });
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قراءة المستندات: $error')),
      );
    }
  }

  static String typeLabel(String type) => switch (type) {
        'sales_invoice' => 'فاتورة مبيعات',
        'service_invoice' => 'فاتورة خدمات',
        'purchase_invoice' => 'فاتورة مشتريات',
        'quotation' => 'عرض سعر',
        'rental_quotation' => 'عرض سعر تأجير',
        'receipt_voucher' => 'سند قبض',
        'payment_voucher' => 'سند صرف',
        'official_letter' => 'خطاب رسمي',
        'employment_contract' => 'عقد عمل',
        'financial_claim' => 'مطالبة مالية',
        'customer_statement' => 'كشف حساب عميل',
        'supplier_statement' => 'كشف حساب مورد',
        'equipment_rental' => 'عقد تأجير معدات',
        'payroll' => 'مسير رواتب',
        'journal_entry' => 'سند قيد',
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) => [
          row['number']?.toString() ?? '',
          row['party_name']?.toString() ?? '',
          typeLabel(row['type'] as String),
        ].join(' ').toLowerCase().contains(_search.trim().toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستندات المحفوظة'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'بحث برقم المستند أو العميل أو النوع',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('لا توجد مستندات محفوظة مطابقة'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final row = visible[index];
                            final date = DateTime.tryParse(row['date'] as String? ?? '');
                            final day = date == null
                                ? ''
                                : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: const Icon(Icons.picture_as_pdf_outlined),
                                title: Text('${typeLabel(row['type'] as String)} • ${row['number']}'),
                                subtitle: Text('${row['party_name'] ?? 'بدون اسم'} • $day'),
                                trailing: const Icon(Icons.visibility_outlined),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SavedDocumentPreviewScreen(
                                      documentId: row['id'] as int,
                                      isJournal: row['_journal'] == true,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class SavedDocumentPreviewScreen extends StatefulWidget {
  const SavedDocumentPreviewScreen({
    required this.documentId,
    this.isJournal = false,
    super.key,
  });

  final int documentId;
  final bool isJournal;

  @override
  State<SavedDocumentPreviewScreen> createState() => _SavedDocumentPreviewScreenState();
}

class _SavedDocumentPreviewScreenState extends State<SavedDocumentPreviewScreen> {
  bool _allowPrint = false;

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final allowed = await SessionController.instance.can(
      widget.isJournal ? 'journals' : 'documents',
      action: 'print',
    );
    if (mounted) setState(() => _allowPrint = allowed);
  }

  Future<Uint8List> _build(PdfPageFormat _) async {
    if (widget.isJournal) return _buildJournalPdf();
    final draft = await ErpRepository.instance.documentDraft(widget.documentId);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    return const DocumentPdfService().build(draft: draft, policy: policy);
  }

  Future<Uint8List> _buildJournalPdf() async {
    final db = await SindarDatabase.instance.database;
    final found = await db.query('journal_entries', where: 'id=?',
        whereArgs: [widget.documentId], limit: 1);
    if (found.isEmpty) throw const FormatException('القيد غير موجود');
    final entry = found.first;
    final lines = await ErpRepository.instance.savedJournalLines(widget.documentId);
    final regular = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final debit = lines.fold<double>(0, (sum, r) => sum + (r['debit'] as num).toDouble());
    final credit = lines.fold<double>(0, (sum, r) => sum + (r['credit'] as num).toDouble());
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('سِندار | سند قيد محاسبي', style: pw.TextStyle(font: bold, fontSize: 19)),
              pw.SizedBox(height: 12),
              pw.Text('رقم القيد: JRN-${widget.documentId.toString().padLeft(6, '0')}'),
              pw.Text('التاريخ: ${(entry['date'] as String).substring(0, 10)}'),
              pw.Text('البيان: ${entry['description'] ?? ''}'),
              pw.SizedBox(height: 18),
              pw.TableHelper.fromTextArray(
                headers: ['الحساب', 'مدين', 'دائن'],
                data: [
                  for (final line in lines)
                    [
                      '${line['account_code']} - ${line['name_ar']}',
                      (line['debit'] as num).toStringAsFixed(2),
                      (line['credit'] as num).toStringAsFixed(2),
                    ],
                  ['الإجمالي', debit.toStringAsFixed(2), credit.toStringAsFixed(2)],
                ],
                headerStyle: pw.TextStyle(font: bold),
                cellStyle: pw.TextStyle(font: regular, fontSize: 10),
                cellAlignment: pw.Alignment.centerRight,
              ),
            ],
          ),
        ),
      ],
    ));
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('عرض المستند المحفوظ')),
        body: PdfPreview(
          build: _build,
          allowPrinting: _allowPrint,
          allowSharing: _allowPrint,
          canChangePageFormat: false,
          canChangeOrientation: false,
          pdfFileName: widget.isJournal
              ? 'journal-${widget.documentId}.pdf'
              : 'document-${widget.documentId}.pdf',
        ),
      );
}
