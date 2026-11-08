import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/rental_pricing.dart';
import '../services/rental_workflow_service.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';
import 'assets_payroll_reports_screens.dart';
import 'equipment_rental_screen.dart';
import 'party_inventory_screens.dart';
import 'saved_documents_screen.dart';

class RentalOperationsScreen extends StatefulWidget {
  const RentalOperationsScreen({super.key});

  @override
  State<RentalOperationsScreen> createState() => _RentalOperationsScreenState();
}

class _RentalOperationsScreenState extends State<RentalOperationsScreen> {
  final _service = const RentalWorkflowService();

  List<Map<String, Object?>> _equipment = const [];
  List<Map<String, Object?>> _rentals = const [];
  List<Map<String, Object?>> _quotes = const [];
  List<Map<String, Object?>> _employees = const [];
  List<PartyRecord> _customers = const [];
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait<Object>([
      _service.equipment(),
      _service.rentals(),
      _service.quotes(),
      ErpRepository.instance.listEmployees(),
      ErpRepository.instance.listParties('customer'),
      SindarDatabase.instance.getLicensePolicy(),
    ]);
    if (!mounted) return;
    setState(() {
      _equipment = results[0] as List<Map<String, Object?>>;
      _rentals = results[1] as List<Map<String, Object?>>;
      _quotes = results[2] as List<Map<String, Object?>>;
      _employees = results[3] as List<Map<String, Object?>>;
      _customers = results[4] as List<PartyRecord>;
      _policy = results[5] as LicensePolicy;
      _loading = false;
    });
  }

  Future<bool> _can(String action) async {
    final allowed = await SessionController.instance.can('assets', action: action);
    if (!allowed && mounted) _message('ليست لديك صلاحية تنفيذ هذه العملية');
    return allowed;
  }

  double _suggestedRate(Map<String, Object?> equipment, RentalPeriod period) {
    final key = switch (period) {
      RentalPeriod.hour => 'hourly_rate',
      RentalPeriod.day => 'daily_rate',
      RentalPeriod.week => 'weekly_rate',
      RentalPeriod.month => 'monthly_rate',
      RentalPeriod.year => 'yearly_rate',
    };
    return (equipment[key] as num?)?.toDouble() ?? 0;
  }

  Future<void> _createOperation({required bool quoteOnly}) async {
    if (!await _can(quoteOnly ? 'add' : 'approve') || !mounted) return;
    if (_customers.isEmpty) {
      _message('أضف عميلاً أولاً');
      return;
    }
    final candidates = quoteOnly
        ? _equipment.where((e) => e['status'] != 'sold').toList()
        : _equipment.where((e) => e['status'] == 'available').toList();
    if (candidates.isEmpty) {
      _message(quoteOnly
          ? 'أضف معدة أولاً من قسم المعدات'
          : 'لا توجد معدة متاحة للتأجير حالياً');
      return;
    }

    int? customerId;
    int? equipmentId;
    int? employeeId;
    RentalPeriod period = RentalPeriod.day;
    DateTime start = DateTime.now();
    bool applyTax = _policy.taxModeEnabled;
    final quantity = TextEditingController(text: '1');
    final rate = TextEditingController(text: '0');
    final notes = TextEditingController();

    Map<String, Object?>? selectedEquipment() {
      for (final row in candidates) {
        if (row['id'] == equipmentId) return row;
      }
      return null;
    }

    void applySuggestion() {
      final equipment = selectedEquipment();
      if (equipment == null) return;
      rate.text = _suggestedRate(equipment, period).toStringAsFixed(2);
    }

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) {
            RentalQuote? live;
            final q = int.tryParse(quantity.text.trim());
            final r = double.tryParse(rate.text.trim());
            try {
              if (q != null && r != null && r > 0) {
                live = RentalQuote.create(
                  period: period, quantity: q, unitRate: r, start: start);
              }
            } on FormatException {
              live = null;
            }
            final vat = live == null || !applyTax || !_policy.taxModeEnabled
                ? 0.0
                : live.total * .15;
            return AlertDialog(
              title: Text(quoteOnly ? 'عرض سعر تأجير' : 'إنشاء عقد تأجير'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: customerId,
                        decoration: const InputDecoration(labelText: 'العميل *'),
                        items: [
                          for (final c in _customers)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => update(() => customerId = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: equipmentId,
                        decoration: const InputDecoration(labelText: 'المعدة *'),
                        items: [
                          for (final e in candidates)
                            DropdownMenuItem(
                              value: e['id'] as int,
                              child: Text(
                                '${e['name']} • ${e['code']}'
                                '${e['status'] == 'available' ? '' : ' • غير متاحة الآن'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => update(() {
                          equipmentId = v;
                          applySuggestion();
                        }),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        initialValue: employeeId,
                        decoration: const InputDecoration(
                          labelText: 'الموظف المسؤول عن التسليم / المتابعة'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null, child: Text('بدون تحديد موظف')),
                          for (final e in _employees)
                            DropdownMenuItem<int?>(
                              value: e['id'] as int,
                              child: Text(e['name'] as String)),
                        ],
                        onChanged: (v) => update(() => employeeId = v),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<RentalPeriod>(
                            initialValue: period,
                            decoration: const InputDecoration(labelText: 'وحدة التأجير'),
                            items: [
                              for (final value in RentalPeriod.values)
                                DropdownMenuItem(
                                  value: value, child: Text(value.label)),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              update(() {
                                period = v;
                                applySuggestion();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: quantity,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'العدد'),
                            onChanged: (_) => update(() {}),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: rate,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'السعر المتفق عليه لكل ${period.label}',
                          helperText:
                              'يمكن تغييره لكل عميل ولا يغير السعر المرجعي للمعدة',
                          suffixText: _policy.currencySymbol,
                        ),
                        onChanged: (_) => update(() {}),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('بداية التأجير'),
                        subtitle: Text(_dateTime(start)),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: dialogContext,
                            initialDate: start,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (date == null || !dialogContext.mounted) return;
                          final time = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (time == null) return;
                          update(() => start = DateTime(
                            date.year, date.month, date.day, time.hour, time.minute));
                        },
                      ),
                      if (_policy.taxModeEnabled)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('فاتورة تأجير ضريبية 15%'),
                          subtitle: const Text(
                            'متاح في وضع السعودية الضريبي فقط'),
                          value: applyTax,
                          onChanged: (v) => update(() => applyTax = v),
                        ),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'شروط / ملاحظات الاتفاق'),
                      ),
                      const SizedBox(height: 10),
                      if (live == null)
                        const Text(
                          'حدد المعدة والمدة وسعر الاتفاق.',
                          style: TextStyle(color: AppColors.red),
                        )
                      else
                        Card(
                          color: AppColors.cream,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('الإرجاع المتوقع: ${_dateTime(live.due.toLocal())}'),
                                Text('قبل الضريبة: ${live.total.toStringAsFixed(2)} '
                                  '${_policy.currencySymbol}'),
                                if (vat > 0)
                                  Text('الضريبة: ${vat.toStringAsFixed(2)} '
                                    '${_policy.currencySymbol}'),
                                Text(
                                  'الإجمالي: ${(live.total + vat).toStringAsFixed(2)} '
                                  '${_policy.currencySymbol}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 17),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: customerId == null ||
                          equipmentId == null ||
                          live == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: Text(quoteOnly ? 'حفظ عرض السعر' : 'اعتماد العقد'),
                ),
              ],
            );
          },
        ),
      );
      if (accepted != true || customerId == null || equipmentId == null) return;
      final q = int.parse(quantity.text.trim());
      final r = double.parse(rate.text.trim());
      if (quoteOnly) {
        final id = await _service.createQuote(
          equipmentId: equipmentId!,
          customerId: customerId!,
          employeeId: employeeId,
          start: start,
          period: period,
          quantity: q,
          agreedRate: r,
          taxInvoice: applyTax,
          notes: notes.text,
        );
        await _refresh();
        if (mounted) {
          await Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
        }
      } else {
        final id = await _service.createRental(
          equipmentId: equipmentId!,
          customerId: customerId!,
          employeeId: employeeId,
          start: start,
          period: period,
          quantity: q,
          agreedRate: r,
          taxInvoice: applyTax,
          notes: notes.text,
        );
        await _refresh();
        if (mounted) {
          await Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
        }
      }
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    } finally {
      quantity.dispose();
      rate.dispose();
      notes.dispose();
    }
  }

  Future<void> _convertQuote(Map<String, Object?> row) async {
    if (!await _can('approve')) return;
    try {
      final id = await _service.convertQuote(row['document_id'] as int);
      await _refresh();
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
      }
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _receipt(Map<String, Object?> rental) async {
    if (!await _can('approve') || !mounted) return;
    final outstanding = (rental['total'] as num).toDouble() -
        (rental['paid_amount'] as num).toDouble();
    if (outstanding <= .005) {
      _message('العقد مسدد بالكامل');
      return;
    }
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    String settlement = '1101';
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text('سند قبض • ${rental['number']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('العميل: ${rental['customer_name']}'),
                Text('المتبقي: ${outstanding.toStringAsFixed(2)} '
                    '${_policy.currencySymbol}'),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'المبلغ المقبوض',
                    suffixText: _policy.currencySymbol,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: settlement,
                  decoration: const InputDecoration(labelText: 'حساب التحصيل'),
                  items: const [
                    DropdownMenuItem(value: '1101', child: Text('الصندوق / نقدي')),
                    DropdownMenuItem(value: '1102', child: Text('الحساب البنكي')),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => settlement = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ سند القبض'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      final value = double.tryParse(amount.text.trim());
      if (value == null || value <= 0 || value > outstanding + .005) {
        throw const FormatException('مبلغ القبض غير صحيح أو يتجاوز المتبقي');
      }
      final id = await ErpRepository.instance.createVoucher(
        receipt: true,
        amount: value,
        partyId: rental['customer_id'] as int,
        partyName: rental['customer_name'] as String?,
        linkedDocumentId: rental['document_id'] as int,
        settlementAccountCode: settlement,
        notes: 'قبض عن عقد التأجير ${rental['number']}',
      );
      await _refresh();
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
      }
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    } finally {
      amount.dispose();
    }
  }

  Future<void> _expense(Map<String, Object?> rental) async {
    if (!await _can('approve') || !mounted) return;
    final description = TextEditingController();
    final amount = TextEditingController();
    String account = '5204';
    String settlement = '1101';
    int? employeeId = rental['employee_id'] as int?;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text('مصروف على العقد • ${rental['number']}'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                      labelText: 'بيان المصروف: نقل / صيانة / تشغيل...'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'قيمة المصروف',
                      suffixText: _policy.currencySymbol),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: account,
                    decoration: const InputDecoration(labelText: 'نوع المصروف'),
                    items: const [
                      DropdownMenuItem(
                        value: '5204', child: Text('صيانة وإصلاح')),
                      DropdownMenuItem(
                        value: '5102', child: Text('نقل وشحن')),
                      DropdownMenuItem(
                        value: '5207', child: Text('مصروف تشغيلي / إداري')),
                    ],
                    onChanged: (v) {
                      if (v != null) update(() => account = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: settlement,
                    decoration: const InputDecoration(labelText: 'طريقة الصرف'),
                    items: const [
                      DropdownMenuItem(value: '1101', child: Text('الصندوق')),
                      DropdownMenuItem(value: '1102', child: Text('البنك')),
                    ],
                    onChanged: (v) {
                      if (v != null) update(() => settlement = v);
                    },
                  ),
                  if (_employees.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: employeeId,
                      decoration: const InputDecoration(
                        labelText: 'الموظف المرتبط بالمصروف'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null, child: Text('بدون موظف')),
                        for (final e in _employees)
                          DropdownMenuItem<int?>(
                            value: e['id'] as int,
                            child: Text(e['name'] as String)),
                      ],
                      onChanged: (v) => update(() => employeeId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ سند الصرف'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      final value = double.tryParse(amount.text.trim());
      if (value == null || value <= 0 || description.text.trim().isEmpty) {
        throw const FormatException('أدخل بيان المصروف وقيمته');
      }
      final id = await _service.addExpense(
        rentalId: rental['id'] as int,
        employeeId: employeeId,
        description: description.text,
        amount: value,
        expenseAccount: account,
        settlementAccount: settlement,
      );
      await _refresh();
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => SavedDocumentPreviewScreen(documentId: id)));
      }
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    } finally {
      description.dispose();
      amount.dispose();
    }
  }

  Future<void> _invoicePreview(Map<String, Object?> rental) async {
    if (!await SessionController.instance.can('documents', action: 'print')) {
      _message('ليست لديك صلاحية الطباعة');
      return;
    }
    try {
      final base =
          await ErpRepository.instance.documentDraft(rental['document_id'] as int);
      final taxable = (rental['vat_total'] as num).toDouble() > .005;
      final hasFullBuyerIdentity =
          (rental['customer_vat_number'] as String?)?.trim().isNotEmpty == true &&
          (rental['customer_cr'] as String?)?.trim().isNotEmpty == true;
      final type = taxable
          ? (hasFullBuyerIdentity
              ? DocumentType.taxInvoice
              : DocumentType.simplifiedTaxInvoice)
          : DocumentType.commercialInvoice;
      final draft = base.copyWith(type: type);
      final bytes = await const DocumentPdfService().build(
        draft: draft, policy: _policy);
      await Printing.layoutPdf(
        name: '${type.titleAr}-${draft.number}',
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      _message('تعذر إنشاء الفاتورة: $error');
    }
  }

  Future<void> _return(Map<String, Object?> rental) async {
    if (!await _can('edit') || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استلام المعدة'),
        content: Text(
          'تأكيد استلام ${rental['equipment_name']} وإتاحتها لعقد جديد؟\n'
          'هذه الخطوة لا تلغي المبالغ المستحقة على العميل.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تم الاستلام')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.markReturned(rental['id'] as int);
      await _refresh();
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _openAndRefresh(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    await _refresh();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final active = _rentals.where((r) => r['status'] == 'active').toList();
    final due = active.fold<double>(
      0,
      (sum, r) => sum +
          (r['total'] as num).toDouble() -
          (r['paid_amount'] as num).toDouble(),
    );
    final openQuotes = _quotes.where((q) => q['status'] == 'open').length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('عمليات التأجير'),
        actions: [
          IconButton(
            tooltip: 'إدارة المعدات',
            onPressed: () => _openAndRefresh(const EquipmentRentalScreen()),
            icon: const Icon(Icons.handyman_outlined)),
          IconButton(
            tooltip: 'إضافة / إدارة العملاء',
            onPressed: () => _openAndRefresh(const PartiesScreen(type: 'customer')),
            icon: const Icon(Icons.person_add_alt_1_outlined)),
          IconButton(
            tooltip: 'الموظفون',
            onPressed: () => _openAndRefresh(const PayrollScreen()),
            icon: const Icon(Icons.badge_outlined)),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('التأجير • ${_policy.moneyLabelAr}',
                          style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(
                          _policy.taxModeEnabled
                              ? 'وضع السعودية الضريبي: يمكنك إصدار فاتورة ضريبية من نفس العقد.'
                              : 'وضع غير ضريبي: لا تظهر حقول ضريبة في عمليات التأجير.',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: FilledButton.icon(
                            onPressed: () => _createOperation(quoteOnly: false),
                            icon: const Icon(Icons.assignment_add),
                            label: const Text('عقد تأجير جديد'),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: OutlinedButton.icon(
                            onPressed: () => _createOperation(quoteOnly: true),
                            icon: const Icon(Icons.request_quote_outlined),
                            label: const Text('عرض سعر'),
                          )),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('عقود نشطة ${active.length}')),
                  Chip(label: Text('عروض مفتوحة $openQuotes')),
                  Chip(label: Text(
                    'مستحق ${due.toStringAsFixed(2)} ${_policy.currencySymbol}')),
                ]),
                const SizedBox(height: 18),
                const Text('العقود',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                if (_rentals.isEmpty)
                  const Card(child: ListTile(title: Text('لا توجد عقود تأجير بعد'))),
                for (final rental in _rentals)
                  _RentalCard(
                    rental: rental,
                    policy: _policy,
                    onReceipt: () => _receipt(rental),
                    onExpense: () => _expense(rental),
                    onContract: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) =>
                        SavedDocumentPreviewScreen(
                          documentId: rental['document_id'] as int))),
                    onInvoice: () => _invoicePreview(rental),
                    onReturn: rental['status'] == 'active'
                        ? () => _return(rental)
                        : null,
                  ),
                const SizedBox(height: 20),
                const Text('عروض أسعار التأجير',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                if (_quotes.isEmpty)
                  const Card(child: ListTile(title: Text('لا توجد عروض تأجير بعد'))),
                for (final quote in _quotes)
                  Card(child: ListTile(
                    leading: const Icon(Icons.request_quote_outlined),
                    title: Text('${quote['number']} • ${quote['equipment_name']}'),
                    subtitle: Text(
                      '${quote['customer_name']} • '
                      '${quote['billing_quantity']} ${_unitLabel(quote['billing_unit'])} • '
                      '${(quote['total'] as num).toDouble().toStringAsFixed(2)} '
                      '${_policy.currencySymbol}'),
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) =>
                        SavedDocumentPreviewScreen(
                          documentId: quote['document_id'] as int))),
                    trailing: quote['status'] == 'open'
                        ? FilledButton.tonal(
                            onPressed: () => _convertQuote(quote),
                            child: const Text('تحويل لعقد'))
                        : const Chip(label: Text('تم التحويل')),
                  )),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  static String _unitLabel(Object? value) => switch (value) {
    'hour' => 'ساعة',
    'day' => 'يوم',
    'week' => 'أسبوع',
    'month' => 'شهر',
    'year' => 'سنة',
    _ => value?.toString() ?? '',
  };

  static String _dateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({
    required this.rental,
    required this.policy,
    required this.onReceipt,
    required this.onExpense,
    required this.onContract,
    required this.onInvoice,
    required this.onReturn,
  });

  final Map<String, Object?> rental;
  final LicensePolicy policy;
  final VoidCallback onReceipt;
  final VoidCallback onExpense;
  final VoidCallback onContract;
  final VoidCallback onInvoice;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final total = (rental['total'] as num).toDouble();
    final paid = (rental['paid_amount'] as num).toDouble();
    final outstanding = total - paid;
    final expenses = (rental['expenses_total'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.gold.withValues(alpha: .16),
                child: const Icon(Icons.handyman_outlined, color: AppColors.navy2)),
              title: Text('${rental['number']} • ${rental['equipment_name']}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(
                '${rental['customer_name']}'
                '${rental['employee_name'] == null ? '' : ' • مسؤول: ${rental['employee_name']}'}\n'
                '${rental['billing_quantity']} '
                '${_RentalOperationsScreenState._unitLabel(rental['billing_unit'])} × '
                '${(rental['billing_rate'] as num).toDouble().toStringAsFixed(2)} '
                '${policy.currencySymbol} • '
                'المتبقي ${outstanding.toStringAsFixed(2)}'),
              isThreeLine: true,
              trailing: Chip(label: Text(
                rental['status'] == 'active' ? 'نشط' : 'مستلم')),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الإجمالي ${total.toStringAsFixed(2)} • '
                  'المقبوض ${paid.toStringAsFixed(2)} • '
                  'مصاريف مرتبطة ${expenses.toStringAsFixed(2)} '
                  '${policy.currencySymbol}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  onPressed: outstanding > .005 ? onReceipt : null,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('سند قبض')),
                OutlinedButton.icon(
                  onPressed: onExpense,
                  icon: const Icon(Icons.money_off_csred_outlined, size: 18),
                  label: const Text('مصروف')),
                OutlinedButton.icon(
                  onPressed: onInvoice,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('فاتورة')),
                OutlinedButton.icon(
                  onPressed: onContract,
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('العقد')),
                if (onReturn != null)
                  TextButton.icon(
                    onPressed: onReturn,
                    icon: const Icon(Icons.assignment_return_outlined, size: 18),
                    label: const Text('استلام')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
