// ignore_for_file: prefer_interpolation_to_compose_strings, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/document_pdf_service.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/session_controller.dart';
import 'universal_scanner_screen.dart';

Future<bool> _requirePermission(
  BuildContext context,
  String module,
  String action,
) async {
  final allowed = await SessionController.instance.can(module, action: action);
  if (!allowed && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ليست لديك صلاحية لتنفيذ هذه العملية')),
    );
  }
  return allowed;
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<PartyRecord> _customers = const [];
  List<ItemRecord> _items = const [];
  List<Map<String, Object?>> _quotes = const [];
  List<Map<String, Object?>> _salesInvoices = const [];
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  bool _loading = true;
  bool _onCredit = false;
  String _settlementAccountCode = '1101';
  bool _b2b = false;
  int? _lastInvoiceId;
  int? _editingInvoiceId;
  int? _customerId;
  int? _itemId;
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  final _buyerVat = TextEditingController();
  final _buyerCr = TextEditingController();
  final List<InvoiceLineInput> _lines = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _buyerVat.dispose();
    _buyerCr.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final customers = await ErpRepository.instance.listParties('customer');
    final items = await ErpRepository.instance.listItems();
    final quotes = await ErpRepository.instance.listQuotations();
    final salesInvoices = await ErpRepository.instance.listSalesInvoices();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _items = items;
      _quotes = quotes;
      _salesInvoices = salesInvoices;
      _policy = policy;
      _loading = false;
    });
  }

  PartyRecord? get _customer {
    for (final customer in _customers) {
      if (customer.id == _customerId) return customer;
    }
    return null;
  }

  ItemRecord? get _selectedItem {
    for (final item in _items) {
      if (item.id == _itemId) return item;
    }
    return null;
  }

  void _addLine() {
    final item = _selectedItem;
    if (item == null) return;
    final qty = double.tryParse(_qty.text) ?? 0;
    final price = double.tryParse(_price.text) ?? item.salePrice;
    if (qty <= 0 || price < 0) return;
    setState(() {
      _lines.add(
        InvoiceLineInput(
          itemId: item.id,
          description: item.name,
          quantity: qty,
          unitPrice: price,
          vatRate: _policy.isTaxEnabled ? .15 : 0,
        ),
      );
      _itemId = null;
      _qty.text = '1';
      _price.text = '0';
    });
  }

  Future<void> _saveInvoice() async {
    final editingId = _editingInvoiceId;
    final action = editingId == null ? 'approve' : 'edit';
    if (!await _requirePermission(context, 'sales', action)) return;
    try {
      final customer = _customer;
      final buyerVat = _policy.isTaxEnabled
          ? (_buyerVat.text.trim().isEmpty
              ? customer?.vatNumber
              : _buyerVat.text.trim())
          : null;
      final buyerCr = _buyerCr.text.trim().isEmpty
          ? customer?.commercialRegistration
          : _buyerCr.text.trim();

      final invoiceId = editingId == null
          ? await ErpRepository.instance.createSalesInvoice(
              lines: _lines,
              onCredit: _onCredit,
              customerId: customer?.id,
              customerName: customer?.name,
              buyerVatNumber: buyerVat,
              buyerCommercialRegistration: buyerCr,
              b2b: _b2b,
              settlementAccountCode: _settlementAccountCode,
            )
          : await ErpRepository.instance.updateSalesInvoice(
              invoiceId: editingId,
              lines: _lines,
              onCredit: _onCredit,
              customerId: customer?.id,
              customerName: customer?.name,
              buyerVatNumber: buyerVat,
              buyerCommercialRegistration: buyerCr,
              b2b: _b2b,
              settlementAccountCode: _settlementAccountCode,
            );
      if (!mounted) return;
      setState(() {
        _lastInvoiceId = invoiceId;
        _editingInvoiceId = null;
        _lines.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editingId == null
                ? 'تم اعتماد الفاتورة وترحيل القيد وتحديث المخزون'
                : 'تم تعديل الفاتورة وإعادة ترحيل المخزون والقيود تلقائياً',
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _editInvoice(Map<String, Object?> invoice) async {
    if (!await _requirePermission(context, 'sales', 'edit')) return;
    final id = invoice['id']! as int;
    final rows = await ErpRepository.instance.documentLines(id);
    if (!mounted) return;

    final payment = invoice['payment_method']! as String;
    setState(() {
      _editingInvoiceId = id;
      _lastInvoiceId = id;
      _customerId = invoice['party_id'] as int?;
      _onCredit = payment == 'credit';
      _settlementAccountCode = payment == 'bank' ? '1102' : '1101';
      _buyerVat.text = invoice['party_vat_number'] as String? ?? '';
      _buyerCr.text =
          invoice['party_commercial_registration'] as String? ?? '';
      _b2b = _policy.isTaxEnabled &&
          _buyerVat.text.isNotEmpty &&
          _buyerCr.text.isNotEmpty;
      _lines
        ..clear()
        ..addAll([
          for (final row in rows)
            InvoiceLineInput(
              itemId: row['item_id'] as int?,
              description: row['description']! as String,
              quantity: (row['quantity'] as num).toDouble(),
              unitPrice: (row['unit_price'] as num).toDouble(),
              vatRate: _policy.isTaxEnabled
                  ? (row['vat_rate'] as num).toDouble()
                  : 0,
            ),
        ]);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingInvoiceId = null;
      _lines.clear();
      _customerId = null;
      _buyerVat.clear();
      _buyerCr.clear();
      _b2b = false;
      _onCredit = false;
      _settlementAccountCode = '1101';
    });
  }

  Future<void> _previewLastInvoice() async {
    final id = _lastInvoiceId;
    if (id == null) return;
    if (!await _requirePermission(context, 'sales', 'print')) return;
    try {
      final draft = await ErpRepository.instance.documentDraft(id);
      final policy = await SindarDatabase.instance.getLicensePolicy();
      final bytes = await const DocumentPdfService().build(
        draft: draft,
        policy: policy,
      );
      await Printing.layoutPdf(
        name: '${draft.type.titleAr}-${draft.number}',
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _saveQuote() async {
    if (!await _requirePermission(context, 'sales', 'add')) return;
    try {
      final customer = _customer;
      await ErpRepository.instance.createQuotation(
        lines: _lines,
        customerId: customer?.id,
        customerName: customer?.name,
        buyerVatNumber: _policy.isTaxEnabled
            ? (_buyerVat.text.trim().isEmpty
                ? customer?.vatNumber
                : _buyerVat.text.trim())
            : null,
        buyerCommercialRegistration: _buyerCr.text.trim().isEmpty
            ? customer?.commercialRegistration
            : _buyerCr.text.trim(),
      );
      if (!mounted) return;
      setState(_lines.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ عرض السعر دون إنشاء قيد محاسبي')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _convertQuote(int id) async {
    if (!await _requirePermission(context, 'sales', 'approve')) return;
    try {
      await ErpRepository.instance.convertQuotationToInvoice(
        id,
        onCredit: _onCredit,
        settlementAccountCode: _settlementAccountCode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحويل عرض السعر إلى فاتورة وترحيلها محاسبياً')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  double get _total => _lines.fold<double>(0, (sum, line) {
        final vatRate = _policy.isTaxEnabled ? .15 : 0;
        return sum + line.net + (line.net * vatRate);
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات وعروض الأسعار')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_policy.isTaxEnabled)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('الوضع الضريبي مقفل'),
                subtitle: Text('سيتم إصدار فواتير مبيعات تجارية بدون حقول ضريبية.'),
              ),
            ),
          if (_editingInvoiceId != null) ...[
            Card(
              color: const Color(0xFFFFF6DC),
              child: ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(
                  'وضع تعديل الفاتورة رقم ' +
                      _editingInvoiceId.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'عند الحفظ ستتم استعادة المخزون والقيود القديمة ثم إعادة الترحيل.',
                ),
                trailing: TextButton(
                  onPressed: _cancelEdit,
                  child: const Text('إلغاء التعديل'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<int?>(
            key: ValueKey(_customerId),
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'العميل'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('عميل نقدي / بدون تسجيل')),
              for (final customer in _customers)
                DropdownMenuItem<int?>(value: customer.id, child: Text(customer.name)),
            ],
            onChanged: (value) {
              setState(() {
                _customerId = value;
                final customer = _customer;
                if (customer != null) {
                  _buyerVat.text = customer.vatNumber ?? '';
                  _buyerCr.text = customer.commercialRegistration ?? '';
                }
              });
            },
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('بيع آجل'),
            subtitle: const Text('الفاتورة الآجلة تتطلب عميلاً مسجلاً وتُرحّل إلى الذمم المدينة'),
            value: _onCredit,
            onChanged: (value) => setState(() => _onCredit = value),
          ),
          if (!_onCredit) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey(_settlementAccountCode),
              initialValue: _settlementAccountCode,
              decoration: const InputDecoration(
                labelText: 'حساب التحصيل',
              ),
              items: const [
                DropdownMenuItem(
                  value: '1101',
                  child: Text('الصندوق / نقدي'),
                ),
                DropdownMenuItem(
                  value: '1102',
                  child: Text('الحساب البنكي'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _settlementAccountCode = value);
                }
              },
            ),
          ],
          if (_policy.isTaxEnabled) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('فاتورة ضريبية كاملة B2B'),
              subtitle: const Text('تتطلب الرقم الضريبي للعميل والسجل التجاري'),
              value: _b2b,
              onChanged: (value) => setState(() => _b2b = value),
            ),
            if (_b2b)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buyerVat,
                      keyboardType: TextInputType.number,
                      maxLength: 15,
                      decoration: const InputDecoration(labelText: 'رقم ضريبة العميل'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _buyerCr,
                      decoration: const InputDecoration(labelText: 'السجل التجاري'),
                    ),
                  ),
                ],
              ),
          ],
          const Divider(height: 28),
          const Text('بنود الفاتورة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            key: ValueKey(_itemId),
            initialValue: _itemId,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('اختر صنفاً')),
              for (final item in _items)
                DropdownMenuItem<int?>(
                  value: item.id,
                  child: Text(item.name + ' — متوفر ' + item.quantity.toStringAsFixed(2)),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _itemId = value;
                final item = _selectedItem;
                if (item != null) {
                  _price.text = item.salePrice.toStringAsFixed(2);
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'السعر'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _itemId == null ? null : _addLine,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < _lines.length; index++)
            Card(
              child: ListTile(
                title: Text(_lines[index].description),
                subtitle: Text(
                  _lines[index].quantity.toStringAsFixed(2) +
                      ' × ' +
                      _lines[index].unitPrice.toStringAsFixed(2),
                ),
                trailing: IconButton(
                  onPressed: () => setState(() => _lines.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          if (_lines.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'الإجمالي: ' +
                    _total.toStringAsFixed(2) +
                    ' ' +
                    _policy.currencySymbol,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _lines.isEmpty ? null : _saveQuote,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('حفظ عرض سعر'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _lines.isEmpty ? null : _saveInvoice,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _editingInvoiceId == null
                        ? 'اعتماد الفاتورة'
                        : 'حفظ تعديل الفاتورة',
                  ),
                ),
              ),
            ],
          ),
          if (_lastInvoiceId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _previewLastInvoice,
              icon: const Icon(Icons.qr_code_2_outlined),
              label: Text(
                _policy.isTaxEnabled
                    ? 'معاينة / طباعة الفاتورة مع QR ZATCA'
                    : 'معاينة / طباعة الفاتورة التجارية',
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'فواتير المبيعات',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final invoice in _salesInvoices.take(8))
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(invoice['number']! as String),
                subtitle: Text(
                  (invoice['party_name'] as String? ?? 'عميل نقدي') +
                      ' • ' +
                      (invoice['total'] as num).toDouble().toStringAsFixed(2) +
                      ' ' +
                      _policy.currencySymbol,
                ),
                trailing: IconButton(
                  tooltip: 'تعديل الفاتورة',
                  onPressed: () => _editInvoice(invoice),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text('عروض الأسعار', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final quote in _quotes)
            Card(
              child: ListTile(
                title: Text(quote['number']! as String),
                subtitle: Text(
                  (quote['party_name'] as String? ?? 'بدون عميل') +
                      ' • ' +
                      (quote['total'] as num).toDouble().toStringAsFixed(2),
                ),
                trailing: (quote['status'] as String) == 'converted'
                    ? const Chip(label: Text('تم التحويل'))
                    : FilledButton.tonal(
                        onPressed: () => _convertQuote(quote['id']! as int),
                        child: const Text('تحويل لفاتورة'),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<PartyRecord> _suppliers = const [];
  List<ItemRecord> _items = const [];
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  bool _loading = true;
  bool _onCredit = false;
  String _settlementAccountCode = '1101';
  int? _supplierId;
  int? _itemId;
  final _manualSupplier = TextEditingController();
  final _supplierVat = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  final List<InvoiceLineInput> _lines = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _manualSupplier.dispose();
    _supplierVat.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final suppliers = await ErpRepository.instance.listParties('supplier');
    final items = await ErpRepository.instance.listItems();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      _items = items;
      _policy = policy;
      _loading = false;
    });
  }

  PartyRecord? get _supplier {
    for (final row in _suppliers) {
      if (row.id == _supplierId) return row;
    }
    return null;
  }

  ItemRecord? get _item {
    for (final row in _items) {
      if (row.id == _itemId) return row;
    }
    return null;
  }

  void _addLine() {
    final item = _item;
    if (item == null) return;
    final qty = double.tryParse(_qty.text) ?? 0;
    final price = double.tryParse(_price.text) ?? item.purchasePrice;
    if (qty <= 0 || price < 0) return;
    setState(() {
      _lines.add(
        InvoiceLineInput(
          itemId: item.id,
          description: item.name,
          quantity: qty,
          unitPrice: price,
          vatRate: _policy.isTaxEnabled ? .15 : 0,
        ),
      );
      _itemId = null;
      _qty.text = '1';
      _price.text = '0';
    });
  }

  Future<void> _scan() async {
    if (!await _requirePermission(context, 'purchases', 'add')) return;
    final result = await Navigator.of(context).push<UniversalBarcodeResult>(
      MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
    );
    if (result == null) return;
    final prefill = PurchaseScanPrefill.fromScan(result);
    if (!mounted) return;
    setState(() {
      if (prefill.supplierName != null) {
        _manualSupplier.text = prefill.supplierName!;
      }
      if (prefill.supplierVatNumber != null) {
        _supplierVat.text = prefill.supplierVatNumber!;
      }
      if (prefill.total != null) {
        final vat = prefill.vatTotal ?? 0.0;
        final net = prefill.total! - vat;
        final rate = net > 0 ? vat / net : 0.0;
        _lines.add(
          InvoiceLineInput(
            description: 'فاتورة مورد ممسوحة بالباركود',
            quantity: 1,
            unitPrice: net,
            vatRate: _policy.isTaxEnabled ? rate : 0.0,
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    if (!await _requirePermission(context, 'purchases', 'approve')) return;
    try {
      final supplier = _supplier;
      await ErpRepository.instance.createPurchase(
        lines: _lines,
        onCredit: _onCredit,
        supplierId: supplier?.id,
        supplierName: supplier?.name ?? _manualSupplier.text,
        supplierVatNumber: supplier?.vatNumber ?? _supplierVat.text,
        settlementAccountCode: _settlementAccountCode,
      );
      if (!mounted) return;
      setState(_lines.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المشتريات وتحديث المخزون وترحيل القيد')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('المشتريات'),
        actions: [
          IconButton(
            tooltip: 'مسح فاتورة مورد / باركود',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int?>(
            key: ValueKey(_supplierId),
            initialValue: _supplierId,
            decoration: const InputDecoration(labelText: 'مورد ثابت'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('مورد عابر / نقدي')),
              for (final supplier in _suppliers)
                DropdownMenuItem<int?>(value: supplier.id, child: Text(supplier.name)),
            ],
            onChanged: (value) {
              setState(() {
                _supplierId = value;
                if (value == null) _onCredit = false;
                final supplier = _supplier;
                if (supplier != null) {
                  _manualSupplier.text = supplier.name;
                  _supplierVat.text = supplier.vatNumber ?? '';
                }
              });
            },
          ),
          const SizedBox(height: 8),
          if (_supplierId == null)
            TextField(
              controller: _manualSupplier,
              decoration: const InputDecoration(labelText: 'اسم المورد العابر'),
            ),
          if (_policy.isTaxEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _supplierVat,
              keyboardType: TextInputType.number,
              maxLength: 15,
              decoration: const InputDecoration(labelText: 'الرقم الضريبي للمورد'),
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('شراء آجل'),
            subtitle: const Text('عند المورد الثابت يتم تحديث كشف حسابه تلقائياً'),
            value: _onCredit,
            onChanged: _supplierId == null
                ? null
                : (value) => setState(() => _onCredit = value),
          ),

          if (!_onCredit) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey(_settlementAccountCode),
              initialValue: _settlementAccountCode,
              decoration: const InputDecoration(
                labelText: 'حساب السداد',
              ),
              items: const [
                DropdownMenuItem(
                  value: '1101',
                  child: Text('الصندوق / نقدي'),
                ),
                DropdownMenuItem(
                  value: '1102',
                  child: Text('الحساب البنكي'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _settlementAccountCode = value);
                }
              },
            ),
          ],          const Divider(height: 28),
          DropdownButtonFormField<int?>(
            key: ValueKey(_itemId),
            initialValue: _itemId,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('اختر صنفاً')),
              for (final item in _items)
                DropdownMenuItem<int?>(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) {
              setState(() {
                _itemId = value;
                final item = _item;
                if (item != null) {
                  _price.text = item.purchasePrice.toStringAsFixed(2);
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'سعر الشراء'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _itemId == null ? null : _addLine,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < _lines.length; index++)
            Card(
              child: ListTile(
                title: Text(_lines[index].description),
                subtitle: Text(
                  _lines[index].quantity.toStringAsFixed(2) +
                      ' × ' +
                      _lines[index].unitPrice.toStringAsFixed(2),
                ),
                trailing: IconButton(
                  onPressed: () => setState(() => _lines.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('اعتماد فاتورة المشتريات'),
          ),
        ],
      ),
    );
  }
}
