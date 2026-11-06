import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/party_statement_pdf_service.dart';
import 'document_studio_screen.dart';

class JournalOperationsScreen extends StatefulWidget {
  const JournalOperationsScreen({super.key});

  @override
  State<JournalOperationsScreen> createState() => _JournalOperationsScreenState();
}

class _JournalOperationsScreenState extends State<JournalOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Account> _accounts = const [];
  String? _fromAccount;
  String? _toAccount;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final List<_CompoundLine> _compound = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _amount.dispose();
    _description.dispose();
    for (final line in _compound) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await SindarDatabase.instance.getAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts.where((account) => account.isPosting).toList(growable: false);
    });
  }

  Future<void> _saveQuick() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (_fromAccount == null || _toAccount == null || amount <= 0) return;
    try {
      await ErpRepository.instance.postJournal(
        JournalDraft(
          date: DateTime.now().toUtc(),
          description: _description.text.trim().isEmpty
              ? 'قيد سريع'
              : _description.text.trim(),
          referenceType: 'quick_journal',
          lines: [
            JournalLineDraft(accountCode: _toAccount!, debit: amount),
            JournalLineDraft(accountCode: _fromAccount!, credit: amount),
          ],
        ),
      );
      if (!mounted) return;
      _amount.clear();
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ترحيل القيد السريع بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _addCompoundLine() async {
    String? account;
    final debit = TextEditingController(text: '0');
    final credit = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إضافة طرف للقيد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: account,
                decoration: const InputDecoration(labelText: 'الحساب'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('اختر الحساب'),
                  ),
                  for (final item in _accounts)
                    DropdownMenuItem<String?>(
                      value: item.code,
                      child: Text(item.code + ' — ' + item.nameAr),
                    ),
                ],
                onChanged: (value) => setLocalState(() => account = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: debit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'مدين'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: credit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'دائن'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (accepted == true && account != null) {
      setState(() {
        _compound.add(
          _CompoundLine(
            accountCode: account!,
            debit: double.tryParse(debit.text) ?? 0,
            credit: double.tryParse(credit.text) ?? 0,
          ),
        );
      });
    }
    debit.dispose();
    credit.dispose();
  }

  Future<void> _saveCompound() async {
    final draft = JournalDraft(
      date: DateTime.now().toUtc(),
      description: _description.text.trim().isEmpty
          ? 'قيد يومية متعدد الأطراف'
          : _description.text.trim(),
      referenceType: 'compound_journal',
      lines: [
        for (final line in _compound)
          JournalLineDraft(
            accountCode: line.accountCode,
            debit: line.debit,
            credit: line.credit,
          ),
      ],
    );
    try {
      draft.validate();
      await ErpRepository.instance.postJournal(draft);
      if (!mounted) return;
      setState(_compound.clear);
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم اعتماد القيد المتوازن')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDebit = _compound.fold<double>(0, (sum, line) => sum + line.debit);
    final totalCredit = _compound.fold<double>(0, (sum, line) => sum + line.credit);
    return Scaffold(
      appBar: AppBar(
        title: const Text('القيود اليومية'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'قيد سريع'),
            Tab(text: 'قيد متعدد الأطراف'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'قيد مبسط لغير المحاسبين',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_fromAccount),
                initialValue: _fromAccount,
                decoration: const InputDecoration(labelText: 'من حساب'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('اختر')),
                  for (final item in _accounts)
                    DropdownMenuItem<String?>(
                      value: item.code,
                      child: Text(item.code + ' — ' + item.nameAr),
                    ),
                ],
                onChanged: (value) => setState(() => _fromAccount = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey(_toAccount),
                initialValue: _toAccount,
                decoration: const InputDecoration(labelText: 'إلى حساب'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('اختر')),
                  for (final item in _accounts)
                    DropdownMenuItem<String?>(
                      value: item.code,
                      child: Text(item.code + ' — ' + item.nameAr),
                    ),
                ],
                onChanged: (value) => setState(() => _toAccount = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'البيان'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saveQuick,
                icon: const Icon(Icons.check),
                label: const Text('ترحيل القيد'),
              ),
            ],
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'بيان القيد'),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < _compound.length; index++)
                Card(
                  child: ListTile(
                    title: Text(_compound[index].accountCode),
                    subtitle: Text(
                      'مدين ' +
                          _compound[index].debit.toStringAsFixed(2) +
                          ' • دائن ' +
                          _compound[index].credit.toStringAsFixed(2),
                    ),
                    trailing: IconButton(
                      onPressed: () => setState(() {
                        _compound[index].dispose();
                        _compound.removeAt(index);
                      }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _addCompoundLine,
                icon: const Icon(Icons.add),
                label: const Text('إضافة طرف'),
              ),
              const SizedBox(height: 12),
              Text(
                'إجمالي المدين: ' +
                    totalDebit.toStringAsFixed(2) +
                    '   |   إجمالي الدائن: ' +
                    totalCredit.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: (totalDebit - totalCredit).abs() < .005
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _compound.length < 2 ? null : _saveCompound,
                icon: const Icon(Icons.balance_outlined),
                label: const Text('التحقق والترحيل'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key, required this.receipt});

  final bool receipt;

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  List<PartyRecord> _parties = const [];
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  int? _partyId;
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final parties = await ErpRepository.instance.listParties(
      widget.receipt ? 'customer' : 'supplier',
    );
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _parties = parties;
      _policy = policy;
    });
  }

  PartyRecord? get _party {
    for (final item in _parties) {
      if (item.id == _partyId) return item;
    }
    return null;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return;
    try {
      await ErpRepository.instance.createVoucher(
        receipt: widget.receipt,
        amount: amount,
        partyId: _party?.id,
        partyName: _party?.name,
        notes: _notes.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.receipt
                ? 'تم إنشاء سند القبض وترحيل القيد'
                : 'تم إنشاء سند الصرف وترحيل القيد',
          ),
        ),
      );
      _amount.clear();
      _notes.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _preview() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return;
    final draft = DocumentDraft(
      type: widget.receipt
          ? DocumentType.receiptVoucher
          : DocumentType.paymentVoucher,
      number: widget.receipt ? 'REC-PREVIEW' : 'PAY-PREVIEW',
      date: DateTime.now(),
      company: const CompanyProfile(
        nameAr: 'مؤسسة سندار التجارية',
        nameEn: 'SINDAR Trading Est.',
        commercialRegistration: '1010101010',
      ),
      lines: [
        DocumentLine(
          description: _notes.text.trim().isEmpty ? 'دفعة مالية' : _notes.text.trim(),
          quantity: 1,
          unitPrice: amount,
        ),
      ],
      contacts: const [],
      identity: const DocumentIdentity(),
      partyName: _party?.name,
    );
    final bytes = await const DocumentPdfService().build(
      draft: draft,
      policy: _policy,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.receipt ? 'سند قبض' : 'سند صرف';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int?>(
            key: ValueKey(_partyId),
            initialValue: _partyId,
            decoration: InputDecoration(
              labelText: widget.receipt ? 'العميل' : 'المورد',
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('بدون ربط بطرف')),
              for (final party in _parties)
                DropdownMenuItem<int?>(value: party.id, child: Text(party.name)),
            ],
            onChanged: (value) => setState(() => _partyId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'المبلغ ' + _policy.currencySymbol,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'البيان / جدول الدفعة'),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _amount,
            builder: (_, value, __) {
              final amount = double.tryParse(value.text) ?? 0;
              return Text(
                'التفقيط: ' + ArabicAmountInWords.spell(amount),
                style: const TextStyle(fontWeight: FontWeight.w800),
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('معاينة PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('حفظ ' + title),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MoreDocumentsScreen extends StatefulWidget {
  const MoreDocumentsScreen({super.key});

  @override
  State<MoreDocumentsScreen> createState() => _MoreDocumentsScreenState();
}

class _MoreDocumentsScreenState extends State<MoreDocumentsScreen> {
  List<PartyRecord> _customers = const [];
  int? _customerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customers = await ErpRepository.instance.listParties('customer');
    if (!mounted) return;
    setState(() => _customers = customers);
  }

  PartyRecord? get _customer {
    for (final item in _customers) {
      if (item.id == _customerId) return item;
    }
    return null;
  }

  Future<void> _claim() async {
    final customer = _customer;
    if (customer == null) return;
    final invoices = await ErpRepository.instance.unpaidInvoices(customer.id);
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final bytes = await const PartyStatementPdfService().buildClaim(
      party: customer,
      invoices: invoices,
      policy: policy,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'claim-' + customer.id.toString() + '.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مستندات أخرى')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('خطاب رسمي'),
              subtitle: const Text('إنشاء خطاب بالترويسة الرسمية بدون باركود'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DocumentStudioScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'مطالبة مالية من رصيد العميل وفواتيره غير المسددة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            key: ValueKey(_customerId),
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'العميل'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('اختر العميل')),
              for (final customer in _customers)
                DropdownMenuItem<int?>(value: customer.id, child: Text(customer.name)),
            ],
            onChanged: (value) => setState(() => _customerId = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _customerId == null ? null : _claim,
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('إصدار ومشاركة المطالبة المالية'),
          ),
        ],
      ),
    );
  }
}

class _CompoundLine {
  _CompoundLine({
    required this.accountCode,
    required this.debit,
    required this.credit,
  });

  final String accountCode;
  final double debit;
  final double credit;

  void dispose() {}
}
