// ignore_for_file: prefer_interpolation_to_compose_strings, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sindar_core/sindar_core.dart';
import '../data/local/sindar_database.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/party_statement_pdf_service.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';
import 'universal_scanner_screen.dart';

class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, required this.type});

  final String type;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  List<PartyRecord> _parties = const [];
  bool _loading = true;

  bool get _customer => widget.type == 'customer';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rows = await ErpRepository.instance.listParties(widget.type);
    if (!mounted) return;
    setState(() {
      _parties = rows;
      _loading = false;
    });
  }

  Future<void> _addParty() async {
    final module = _customer ? 'customers' : 'suppliers';
    if (!await SessionController.instance.can(module, action: 'add')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ليست لديك صلاحية الإضافة')));
      return;
    }
    final name = TextEditingController();
    final vat = TextEditingController();
    final cr = TextEditingController();
    final phone = TextEditingController();
    final credit = TextEditingController(text: '0');
    final opening = TextEditingController(text: '0');
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_customer ? 'إضافة عميل' : 'إضافة مورد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 8),
              if (policy.taxModeEnabled)
                TextField(
                  controller: vat,
                  keyboardType: TextInputType.number,
                  maxLength: 15,
                  decoration: const InputDecoration(labelText: 'الرقم الضريبي'),
                ),
              TextField(controller: cr, decoration: const InputDecoration(labelText: 'السجل التجاري')),
              const SizedBox(height: 8),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
              const SizedBox(height: 8),
              if (_customer)
                TextField(
                  controller: credit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الحد الائتماني'),
                ),
              if (_customer) const SizedBox(height: 8),
              TextField(
                controller: opening,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );

    if (accepted == true && name.text.trim().isNotEmpty) {
      await ErpRepository.instance.addParty(
        type: widget.type,
        name: name.text,
        vatNumber: vat.text,
        commercialRegistration: cr.text,
        phone: phone.text,
        creditLimit: double.tryParse(credit.text) ?? 0,
        openingBalance: double.tryParse(opening.text) ?? 0,
      );
      await _refresh();
    }

    name.dispose();
    vat.dispose();
    cr.dispose();
    phone.dispose();
    credit.dispose();
    opening.dispose();
  }

  Future<void> _showStatement(PartyRecord party) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      helpText: _customer ? 'فترة كشف حساب العميل' : 'فترة كشف حساب المورد',
      cancelText: 'كل الفترة',
      confirmText: 'عرض',
    );
    if (!mounted) return;

    final rows = await ErpRepository.instance.partyStatement(
      party.id,
      from: range?.start,
      to: range?.end,
    );
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .92,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${_customer ? 'كشف حساب: ' : 'كشف حساب مورد: '}${party.name}',
            ),
            actions: [
              IconButton(
                tooltip: 'طباعة / مشاركة كشف الحساب',
                onPressed: () async {
                  final module = _customer ? 'customers' : 'suppliers';
                  final allowed = await SessionController.instance.can(
                    module,
                    action: 'print',
                  );
                  if (!allowed) {
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(
                          content: Text('ليست لديك صلاحية طباعة كشف الحساب'),
                        ),
                      );
                    }
                    return;
                  }
                  final bytes =
                      await const PartyStatementPdfService().buildStatement(
                    party: party,
                    rows: rows,
                    policy: policy,
                  );
                  await Printing.layoutPdf(onLayout: (_) async => bytes);
                },
                icon: const Icon(Icons.print_outlined),
              ),
              if (_customer)
                IconButton(
                  tooltip: 'مطالبة مالية',
                  onPressed: () async {
                    final allowed = await SessionController.instance.can(
                      'documents',
                      action: 'print',
                    );
                    if (!allowed) {
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('ليست لديك صلاحية إصدار المطالبات'),
                          ),
                        );
                      }
                      return;
                    }
                    final invoices =
                        await ErpRepository.instance.unpaidInvoices(party.id);
                    final bytes =
                        await const PartyStatementPdfService().buildClaim(
                      party: party,
                      invoices: invoices,
                      policy: policy,
                    );
                    await Printing.sharePdf(
                      bytes: bytes,
                      filename: 'claim-${party.id}.pdf',
                    );
                  },
                  icon: const Icon(Icons.request_quote_outlined),
                ),
            ],
          ),
          body: Column(
            children: [
              if (range != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      avatar: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        '${_date(range.start)} — ${_date(range.end)}',
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('لا توجد حركات لهذا الحساب في الفترة'),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('المستند')),
                            DataColumn(label: Text('العملية')),
                            DataColumn(label: Text('مدين')),
                            DataColumn(label: Text('دائن')),
                            DataColumn(label: Text('الرصيد')),
                          ],
                          rows: [
                            for (final row in rows)
                              DataRow(
                                cells: [
                                  DataCell(Text(_date(row.date))),
                                  DataCell(Text(row.reference)),
                                  DataCell(Text(row.operationType)),
                                  DataCell(
                                    Text(row.debit.toStringAsFixed(2)),
                                  ),
                                  DataCell(
                                    Text(row.credit.toStringAsFixed(2)),
                                  ),
                                  DataCell(
                                    Text(row.balance.toStringAsFixed(2)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return value.year.toString() + '-' + m + '-' + d;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_customer ? 'العملاء' : 'الموردون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addParty,
        icon: const Icon(Icons.add),
        label: Text(_customer ? 'عميل جديد' : 'مورد جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _parties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final party = _parties[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.gold.withValues(alpha: .18),
                        child: Icon(
                          _customer ? Icons.person_outline : Icons.local_shipping_outlined,
                          color: AppColors.navy2,
                        ),
                      ),
                      title: Text(party.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        [
                          if (party.phone != null) party.phone!,
                          if (party.vatNumber != null) 'ضريبي: ' + party.vatNumber!,
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => _showStatement(party),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<ItemRecord> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rows = await ErpRepository.instance.listItems();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _scanAndAdd() async {
    if (!await SessionController.instance.can('inventory', action: 'add')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ليست لديك صلاحية إضافة الأصناف')),
        );
      }
      return;
    }
    final result = await Navigator.of(context).push<UniversalBarcodeResult>(
      MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
    );
    if (result == null || !mounted) return;
    await _add(scannedBarcode: result.rawValue);
  }

  Future<void> _add({String? scannedBarcode}) async {
    if (!await SessionController.instance.can('inventory', action: 'add')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ليست لديك صلاحية إضافة الأصناف')));
      return;
    }
    final code = TextEditingController();
    final barcode = TextEditingController(text: scannedBarcode ?? '');
    final name = TextEditingController();
    final purchase = TextEditingController(text: '0');
    final sale = TextEditingController(text: '0');
    final qty = TextEditingController(text: '0');
    final reorder = TextEditingController(text: '0');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة صنف'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'الكود')),
              const SizedBox(height: 8),
              TextField(controller: barcode, decoration: const InputDecoration(labelText: 'الباركود')),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الصنف')),
              const SizedBox(height: 8),
              TextField(controller: purchase, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الشراء')),
              const SizedBox(height: 8),
              TextField(controller: sale, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر البيع')),
              const SizedBox(height: 8),
              TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية الحالية')),
              const SizedBox(height: 8),
              TextField(controller: reorder, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حد الطلب')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );

    if (accepted == true && code.text.trim().isNotEmpty && name.text.trim().isNotEmpty) {
      await ErpRepository.instance.addItem(
        code: code.text,
        barcode: barcode.text,
        name: name.text,
        purchasePrice: double.tryParse(purchase.text) ?? 0,
        salePrice: double.tryParse(sale.text) ?? 0,
        quantity: double.tryParse(qty.text) ?? 0,
        reorderLevel: double.tryParse(reorder.text) ?? 0,
      );
      await _refresh();
    }

    code.dispose();
    barcode.dispose();
    name.dispose();
    purchase.dispose();
    sale.dispose();
    qty.dispose();
    reorder.dispose();
  }

  Future<void> _editPrices(ItemRecord item) async {
    if (!await SessionController.instance.can('inventory', action: 'edit')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ليس لديك صلاحية تعديل الأصناف')));
      }
      return;
    }
    if (!mounted) return;
    final purchase = TextEditingController(
      text: item.purchasePrice.toStringAsFixed(2));
    final sale = TextEditingController(
      text: item.salePrice.toStringAsFixed(2));
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('تعديل أسعار ${item.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: purchase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'سعر الشراء للصنف')),
            const SizedBox(height: 12),
            TextField(controller: sale,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'سعر البيع للصنف')),
            const SizedBox(height: 12),
            const Text('التعديل يطبق على الفواتير الجديدة فقط، '
              'ولا يغير أسعار المستندات المحفوظة.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ الأسعار')),
          ],
        ),
      );
      if (accepted != true) return;
      final p = double.tryParse(purchase.text.trim());
      final s = double.tryParse(sale.text.trim());
      if (p == null || s == null) {
        throw const FormatException('تأكد من إدخال الأسعار بشكل صحيح');
      }
      await ErpRepository.instance.updateItemPrices(
        itemId: item.id, purchasePrice: p, salePrice: s);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تعديل السعر: $error')));
      }
    } finally {
      purchase.dispose();
      sale.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون والأصناف'),
        actions: [
          IconButton(
            tooltip: 'مسح باركود صنف',
            onPressed: _scanAndAdd,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('صنف جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _items[index];
                final low = item.quantity <= item.reorderLevel;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: low
                          ? Colors.red.withValues(alpha: .12)
                          : AppColors.gold.withValues(alpha: .16),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: low ? Colors.red : AppColors.navy2,
                      ),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      'الكود: ' + item.code +
                      ' • الكمية: ' + item.quantity.toStringAsFixed(2) +
                      ' • شراء: ' + item.purchasePrice.toStringAsFixed(2) +
                      ' • بيع: ' + item.salePrice.toStringAsFixed(2),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editPrices(item),
                  ),
                );
              },
            ),
    );
  }
}
