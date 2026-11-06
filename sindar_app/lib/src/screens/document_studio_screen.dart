import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';
import 'universal_scanner_screen.dart';

class DocumentStudioScreen extends StatefulWidget {
  const DocumentStudioScreen({super.key, this.initialType});

  final DocumentType? initialType;

  @override
  State<DocumentStudioScreen> createState() => _DocumentStudioScreenState();
}

class _DocumentStudioScreenState extends State<DocumentStudioScreen> {
  final _pdf = const DocumentPdfService();
  final _number = TextEditingController(text: 'INV-000001');
  final _party = TextEditingController();
  final _sellerVat = TextEditingController(text: '310123456700003');
  final _buyerVat = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <_EditableLine>[
    _EditableLine(description: 'خدمة / صنف', quantity: '1', price: '100'),
  ];
  final _contacts = <ContactChannel>[];

  LicensePolicy _policy = LicensePolicy.lockedDefault;
  DocumentType _type = DocumentType.commercialInvoice;
  DocumentIdentity _identity = const DocumentIdentity();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final contacts = await ErpRepository.instance.footerContacts();
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _contacts
        ..clear()
        ..addAll(contacts);
      _type = widget.initialType ??
          (policy.isTaxEnabled
              ? DocumentType.taxInvoice
              : DocumentType.commercialInvoice);
      if (!policy.isTaxEnabled && _type.isTaxInvoice) {
        _type = DocumentType.commercialInvoice;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _party.dispose();
    _sellerVat.dispose();
    _buyerVat.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<DocumentType> get _availableTypes => [
        if (_policy.isTaxEnabled) DocumentType.simplifiedTaxInvoice,
        if (_policy.isTaxEnabled) DocumentType.taxInvoice,
        DocumentType.commercialInvoice,
        DocumentType.quotation,
        DocumentType.receiptVoucher,
        DocumentType.paymentVoucher,
        DocumentType.officialLetter,
        DocumentType.financialClaim,
        DocumentType.customerStatement,
        DocumentType.supplierStatement,
      ];

  DocumentDraft _draft() {
    final lines = _lines.map((line) {
      return DocumentLine(
        description: line.description.text.trim().isEmpty
            ? 'بند'
            : line.description.text.trim(),
        quantity: double.tryParse(line.quantity.text) ?? 0,
        unitPrice: double.tryParse(line.price.text) ?? 0,
        vatRate: _policy.isTaxEnabled && _type.isTaxInvoice ? .15 : 0,
      );
    }).toList(growable: false);

    return DocumentDraft(
      type: _type,
      number: _number.text.trim().isEmpty ? 'DOC-1' : _number.text.trim(),
      date: DateTime.now(),
      company: CompanyProfile(
        nameAr: 'مؤسسة سندار التجارية',
        nameEn: 'SINDAR Trading Est.',
        commercialRegistration: '1010101010',
        vatNumber: _policy.isTaxEnabled ? _sellerVat.text.trim() : null,
      ),
      lines: lines,
      contacts: List.unmodifiable(_contacts),
      identity: _identity,
      partyName: _party.text.trim().isEmpty ? null : _party.text.trim(),
      buyerVatNumber: _policy.isTaxEnabled && _buyerVat.text.trim().isNotEmpty
          ? _buyerVat.text.trim()
          : null,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  Future<void> _preview() async {
    if (!await SessionController.instance.can('documents', action: 'print')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ليست لديك صلاحية الطباعة')));
      return;
    }
    try {
      final draft = _draft();
      await Printing.layoutPdf(
        name: '${draft.type.titleAr}-${draft.number}',
        onLayout: (_) => _pdf.build(draft: draft, policy: _policy),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء المستند: $error')),
      );
    }
  }

  Future<void> _share() async {
    if (!await SessionController.instance.can('documents', action: 'print')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ليست لديك صلاحية المشاركة / الطباعة')));
      return;
    }
    try {
      final draft = _draft();
      final bytes = await _pdf.build(draft: draft, policy: _policy);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${draft.number}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر مشاركة المستند: $error')),
      );
    }
  }

  Future<void> _saveStandalone() async {
    if (!await SessionController.instance.can('documents', action: 'add')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ليست لديك صلاحية حفظ المستندات')),
        );
      }
      return;
    }
    try {
      final id = await ErpRepository.instance.saveStandaloneDocument(_draft());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ المستند في SQLite برقم داخلي ' + id.toString())),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<UniversalBarcodeResult>(
      MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
    );
    if (result == null) return;
    final zatca = result.zatca;
    final commercial = result.commercial;
    setState(() {
      if (zatca != null) {
        _party.text = zatca.sellerName;
      } else if (commercial != null) {
        _party.text = commercial.sellerName;
      }
    });
  }

  Future<void> _addContact() async {
    final controller = TextEditingController();
    var type = ContactChannelType.mobile;
    final result = await showDialog<ContactChannel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إضافة رقم / إيميل جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ContactChannelType>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: ContactChannelType.mobile, child: Text('جوال')),
                  DropdownMenuItem(value: ContactChannelType.phone, child: Text('هاتف')),
                  DropdownMenuItem(value: ContactChannelType.email, child: Text('إيميل')),
                  DropdownMenuItem(value: ContactChannelType.website, child: Text('موقع')),
                ],
                onChanged: (value) {
                  if (value != null) setLocalState(() => type = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'القيمة')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(context, ContactChannel(type: type, value: value));
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && mounted) {
      setState(() => _contacts.add(result));
      await ErpRepository.instance.saveFooterContacts(_contacts);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('استوديو المستندات'),
        actions: [
          IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TaxStatus(policy: _policy),
          const SizedBox(height: 14),
          DropdownButtonFormField<DocumentType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'نوع المستند'),
            items: [
              for (final type in _availableTypes)
                DropdownMenuItem(value: type, child: Text(type.titleAr)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'رقم المستند')),
          const SizedBox(height: 12),
          TextField(controller: _party, decoration: const InputDecoration(labelText: 'العميل / المورد / الجهة')),
          if (_policy.isTaxEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _sellerVat,
              keyboardType: TextInputType.number,
              maxLength: 15,
              decoration: const InputDecoration(labelText: 'الرقم الضريبي للبائع'),
            ),
            TextField(
              controller: _buyerVat,
              keyboardType: TextInputType.number,
              maxLength: 15,
              decoration: const InputDecoration(labelText: 'الرقم الضريبي للعميل'),
            ),
          ],
          const SizedBox(height: 6),
          const Text('بنود المستند', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++)
            _LineEditorCard(
              line: _lines[i],
              taxEnabled: _policy.isTaxEnabled && _type.isTaxInvoice,
              onDelete: _lines.length == 1
                  ? null
                  : () => setState(() {
                        _lines[i].dispose();
                        _lines.removeAt(i);
                      }),
            ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add(_EditableLine(description: '', quantity: '1', price: '0'))),
            icon: const Icon(Icons.add),
            label: const Text('إضافة بند'),
          ),
          const SizedBox(height: 14),
          const Text('هوية المستند', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              _ColorPreset(
                color: AppColors.navy2,
                selected: _identity.primaryColorArgb == 0xFF0D2C54,
                onTap: () => setState(() => _identity = const DocumentIdentity()),
              ),
              _ColorPreset(
                color: const Color(0xFF17594A),
                selected: _identity.primaryColorArgb == 0xFF17594A,
                onTap: () => setState(() => _identity = const DocumentIdentity(primaryColorArgb: 0xFF17594A, accentColorArgb: 0xFFD4A017)),
              ),
              _ColorPreset(
                color: const Color(0xFF5B2C6F),
                selected: _identity.primaryColorArgb == 0xFF5B2C6F,
                onTap: () => setState(() => _identity = const DocumentIdentity(primaryColorArgb: 0xFF5B2C6F, accentColorArgb: 0xFFE5A93C)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('بيانات التذييل', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
              TextButton.icon(onPressed: _addContact, icon: const Icon(Icons.add), label: const Text('إضافة رقم/إيميل')),
            ],
          ),
          for (var i = 0; i < _contacts.length; i++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.contact_phone_outlined),
              title: Text(_contacts[i].value),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  setState(() => _contacts.removeAt(i));
                  await ErpRepository.instance.saveFooterContacts(_contacts);
                },
              ),
            ),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'ملاحظات'),
          ),
          const SizedBox(height: 18),
          if (_type == DocumentType.officialLetter ||
              _type == DocumentType.financialClaim) ...[
            FilledButton.tonalIcon(
              onPressed: _saveStandalone,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ المستند في النظام'),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.share_outlined), label: const Text('مشاركة PDF'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(onPressed: _preview, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('معاينة / طباعة'))),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _TaxStatus extends StatelessWidget {
  const _TaxStatus({required this.policy});
  final LicensePolicy policy;

  @override
  Widget build(BuildContext context) {
    final enabled = policy.isTaxEnabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFE8F8F0) : const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(enabled ? Icons.verified_outlined : Icons.lock_outline, color: enabled ? AppColors.green : AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enabled
                  ? 'الوضع الضريبي مفعّل من ترخيص المالك — ${policy.countryCode} / ${policy.currencyCode}'
                  : 'الوضع الضريبي مقفل من ترخيص المالك. جميع حقول الضريبة مخفية والفواتير تجارية.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineEditorCard extends StatelessWidget {
  const _LineEditorCard({
    required this.line,
    required this.taxEnabled,
    required this.onDelete,
  });

  final _EditableLine line;
  final bool taxEnabled;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(controller: line.description, decoration: const InputDecoration(labelText: 'البيان / الصنف')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: line.quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: line.price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر'))),
                if (taxEnabled) ...[
                  const SizedBox(width: 8),
                  const Expanded(child: Text('ضريبة 15%', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                ],
                if (onDelete != null)
                  IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPreset extends StatelessWidget {
  const _ColorPreset({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.gold2 : Colors.transparent, width: 4),
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}

class _EditableLine {
  _EditableLine({
    required String description,
    required String quantity,
    required String price,
  })  : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        price = TextEditingController(text: price);

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController price;

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}
