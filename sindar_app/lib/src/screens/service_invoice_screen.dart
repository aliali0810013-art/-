import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';

class ServiceInvoiceScreen extends StatefulWidget {
  const ServiceInvoiceScreen({super.key});

  @override
  State<ServiceInvoiceScreen> createState() => _ServiceInvoiceScreenState();
}

class _ServiceInvoiceScreenState extends State<ServiceInvoiceScreen> {
  List<PartyRecord> _customers = const [];
  List<Map<String, Object?>> _recent = const [];
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  bool _loading = true;
  bool _onCredit = false;
  bool _applyTax = false;
  String _settlement = '1101';
  int? _customerId;
  int? _lastId;

  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  final _buyerVat = TextEditingController();
  final _buyerCr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _buyerVat.dispose();
    _buyerCr.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final customers = await ErpRepository.instance.listParties('customer');
    final recent = await ErpRepository.instance.listServiceInvoices();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _recent = recent;
      _policy = policy;
      _applyTax = policy.taxModeEnabled && _applyTax;
      _loading = false;
    });
  }

  PartyRecord? get _customer {
    for (final customer in _customers) {
      if (customer.id == _customerId) return customer;
    }
    return null;
  }

  Future<void> _save() async {
    if (!await SessionController.instance.can('sales', action: 'approve')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ليست لديك صلاحية اعتماد الفاتورة')),
        );
      }
      return;
    }
    final quantity = double.tryParse(_quantity.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (quantity == null || quantity <= 0 || price == null || price < 0) {
      _message('تحقق من الكمية والسعر');
      return;
    }
    try {
      final customer = _customer;
      final id = await ErpRepository.instance.createServiceInvoice(
        description: _description.text,
        quantity: quantity,
        unitPrice: price,
        onCredit: _onCredit,
        applyTax: _applyTax,
        customerId: customer?.id,
        customerName: customer?.name,
        buyerVatNumber: _buyerVat.text.trim().isEmpty
            ? customer?.vatNumber
            : _buyerVat.text.trim(),
        buyerCommercialRegistration: _buyerCr.text.trim().isEmpty
            ? customer?.commercialRegistration
            : _buyerCr.text.trim(),
        settlementAccountCode: _settlement,
      );
      if (!mounted) return;
      setState(() {
        _lastId = id;
        _description.clear();
        _quantity.text = '1';
        _price.text = '0';
      });
      _message('تم اعتماد فاتورة الخدمة وترحيلها محاسبياً');
      await _refresh();
    } catch (error) {
      _message(error.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _preview(int id) async {
    if (!await SessionController.instance.can('sales', action: 'print')) return;
    final draft = await ErpRepository.instance.documentDraft(id);
    final bytes = await const DocumentPdfService().build(
      draft: draft, policy: _policy);
    await Printing.layoutPdf(
      name: '${draft.type.titleAr}-${draft.number}',
      onLayout: (_) async => bytes,
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final qty = double.tryParse(_quantity.text) ?? 0;
    final price = double.tryParse(_price.text) ?? 0;
    final net = qty * price;
    final vat = _applyTax && _policy.taxModeEnabled ? net * .15 : 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('فاتورة خدمة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              DropdownButtonFormField<int?>(
                initialValue: _customerId,
                decoration: const InputDecoration(labelText: 'العميل'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null, child: Text('عميل نقدي / بدون تسجيل')),
                  for (final c in _customers)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() {
                  _customerId = value;
                  final customer = _customer;
                  _buyerVat.text = customer?.vatNumber ?? '';
                  _buyerCr.text = customer?.commercialRegistration ?? '';
                  if (value == null) _onCredit = false;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'وصف الخدمة'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية / عدد الخدمات'),
                  onChanged: (_) => setState(() {}),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'السعر • ${_policy.currencyNameAr}'),
                  onChanged: (_) => setState(() {}),
                )),
              ]),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('فاتورة آجلة'),
                subtitle: const Text('تُرحّل إلى ذمة العميل ويُسددها بسند قبض'),
                value: _onCredit,
                onChanged: _customerId == null
                    ? null
                    : (v) => setState(() => _onCredit = v),
              ),
              if (!_onCredit)
                DropdownButtonFormField<String>(
                  initialValue: _settlement,
                  decoration: const InputDecoration(labelText: 'حساب التحصيل'),
                  items: const [
                    DropdownMenuItem(value: '1101', child: Text('الصندوق / نقدي')),
                    DropdownMenuItem(value: '1102', child: Text('الحساب البنكي')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _settlement = v);
                  },
                ),
              if (_policy.taxModeEnabled) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تطبيق ضريبة القيمة المضافة 15%'),
                  subtitle: const Text('تظهر فقط في وضع السعودية الضريبي'),
                  value: _applyTax,
                  onChanged: (v) => setState(() => _applyTax = v),
                ),
                if (_applyTax) ...[
                  TextField(
                    controller: _buyerVat,
                    keyboardType: TextInputType.number,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'الرقم الضريبي للعميل - اختياري للمبسطة'),
                  ),
                  TextField(
                    controller: _buyerCr,
                    decoration: const InputDecoration(
                      labelText: 'السجل التجاري للعميل'),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'الإجمالي: ${(net + vat).toStringAsFixed(2)} '
                  '${_policy.currencySymbol}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _description.text.trim().isEmpty ? null : _save,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('اعتماد فاتورة الخدمة'),
              ),
            ]),
          )),
          if (_lastId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _preview(_lastId!),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('معاينة آخر فاتورة'),
            ),
          ],
          const SizedBox(height: 20),
          const Text('آخر فواتير الخدمات',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد فواتير خدمات بعد'))),
          for (final row in _recent.take(10))
            Card(child: ListTile(
              leading: const Icon(Icons.design_services_outlined),
              title: Text(row['number'] as String),
              subtitle: Text(
                '${row['party_name'] ?? 'بدون اسم'} • '
                '${(row['total'] as num).toDouble().toStringAsFixed(2)} '
                '${_policy.currencySymbol}'),
              trailing: const Icon(Icons.visibility_outlined),
              onTap: () => _preview(row['id'] as int),
            )),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
