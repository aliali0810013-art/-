import 'package:flutter/material.dart';

import '../services/equipment_catalog_service.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';

class EquipmentRentalScreen extends StatefulWidget {
  const EquipmentRentalScreen({super.key});

  @override
  State<EquipmentRentalScreen> createState() => _EquipmentRentalScreenState();
}

class _EquipmentRentalScreenState extends State<EquipmentRentalScreen> {
  final _service = const EquipmentCatalogService();
  List<Map<String, Object?>> _equipment = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rows = await _service.list();
    if (!mounted) return;
    setState(() {
      _equipment = rows;
      _loading = false;
    });
  }

  Future<bool> _authorize(String action) async {
    final allowed = await SessionController.instance.can('assets', action: action);
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية لإدارة المعدات')),
      );
    }
    return allowed;
  }

  Future<void> _openEditor([Map<String, Object?>? equipment]) async {
    final action = equipment == null ? 'add' : 'edit';
    if (!await _authorize(action) || !mounted) return;

    String text(String key) => equipment?[key]?.toString() ?? '';
    String number(String key) =>
        ((equipment?[key] as num?)?.toDouble() ?? 0).toStringAsFixed(2);

    final code = TextEditingController(text: text('code'));
    final name = TextEditingController(text: text('name'));
    final serial = TextEditingController(text: text('serial_number'));
    final brand = TextEditingController(text: text('brand'));
    final model = TextEditingController(text: text('model'));
    final year = TextEditingController(text: text('manufacture_year'));
    final location = TextEditingController(text: text('location'));
    final meter = TextEditingController(text: number('meter_hours'));
    final condition = TextEditingController(text: text('condition_notes'));
    final notes = TextEditingController(text: text('notes'));
    final purchase = TextEditingController(text: number('purchase_price'));
    final market = TextEditingController(text: number('sale_price'));
    final hourly = TextEditingController(text: number('hourly_rate'));
    final daily = TextEditingController(text: number('daily_rate'));
    final weekly = TextEditingController(text: number('weekly_rate'));
    final monthly = TextEditingController(text: number('monthly_rate'));
    final yearly = TextEditingController(text: number('yearly_rate'));
    final controllers = <TextEditingController>[
      code, name, serial, brand, model, year, location, meter, condition, notes,
      purchase, market, hourly, daily, weekly, monthly, yearly,
    ];

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(equipment == null ? 'إضافة معدة' : 'تعديل بطاقة المعدة'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SectionTitle('هوية المعدة'),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'رقم / كود المعدة *'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: serial,
                      decoration: const InputDecoration(labelText: 'الرقم التسلسلي'),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'اسم المعدة *'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: brand,
                      decoration: const InputDecoration(labelText: 'الماركة'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: model,
                      decoration: const InputDecoration(labelText: 'الموديل'),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'سنة الصنع'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: location,
                      decoration: const InputDecoration(labelText: 'الموقع / المستودع'),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: meter,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'عداد ساعات التشغيل'),
                  ),
                  const SizedBox(height: 14),
                  const _SectionTitle('الحالة والملاحظات'),
                  TextField(
                    controller: condition,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'حالة المعدة عند الفحص'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'ملاحظات عامة'),
                  ),
                  const SizedBox(height: 14),
                  const _SectionTitle('القيم المرجعية'),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: purchase,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'تكلفة الاقتناء المرجعية'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: market,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'القيمة السوقية المرجعية'),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  const _SectionTitle('أسعار تأجير مقترحة'),
                  const Text(
                    'هذه الأسعار اقتراح فقط. عند إنشاء العملية يمكن الاتفاق مع كل عميل على سعر مختلف.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _PriceField(controller: hourly, label: 'الساعة')),
                    const SizedBox(width: 8),
                    Expanded(child: _PriceField(controller: daily, label: 'اليوم')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _PriceField(controller: weekly, label: 'الأسبوع')),
                    const SizedBox(width: 8),
                    Expanded(child: _PriceField(controller: monthly, label: 'الشهر')),
                  ]),
                  const SizedBox(height: 8),
                  _PriceField(controller: yearly, label: 'السنة'),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ البطاقة'),
            ),
          ],
        ),
      );
      if (accepted != true) return;

      double value(TextEditingController c) {
        final parsed = double.tryParse(c.text.trim());
        if (parsed == null) throw const FormatException('تأكد من القيم الرقمية');
        return parsed;
      }
      final manufactureYear = year.text.trim().isEmpty
          ? null
          : int.tryParse(year.text.trim());
      if (year.text.trim().isNotEmpty && manufactureYear == null) {
        throw const FormatException('سنة الصنع غير صحيحة');
      }

      if (equipment == null) {
        await _service.add(
          code: code.text,
          name: name.text,
          serialNumber: serial.text,
          brand: brand.text,
          model: model.text,
          manufactureYear: manufactureYear,
          location: location.text,
          meterHours: value(meter),
          conditionNotes: condition.text,
          notes: notes.text,
          purchaseCost: value(purchase),
          marketValue: value(market),
          hourlyRate: value(hourly),
          dailyRate: value(daily),
          weeklyRate: value(weekly),
          monthlyRate: value(monthly),
          yearlyRate: value(yearly),
        );
      } else {
        await _service.update(
          id: equipment['id'] as int,
          code: code.text,
          name: name.text,
          serialNumber: serial.text,
          brand: brand.text,
          model: model.text,
          manufactureYear: manufactureYear,
          location: location.text,
          meterHours: value(meter),
          conditionNotes: condition.text,
          notes: notes.text,
          purchaseCost: value(purchase),
          marketValue: value(market),
          hourlyRate: value(hourly),
          dailyRate: value(daily),
          weeklyRate: value(weekly),
          monthlyRate: value(monthly),
          yearlyRate: value(yearly),
        );
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('FormatException: ', ''))),
        );
      }
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  Future<void> _toggleMaintenance(Map<String, Object?> equipment) async {
    if (!await _authorize('edit')) return;
    try {
      final maintenance = equipment['status'] != 'maintenance';
      await _service.setMaintenance(equipment['id'] as int, maintenance);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('FormatException: ', ''))),
        );
      }
    }
  }

  String _status(String value) => switch (value) {
    'available' => 'متاحة',
    'rented' => 'مؤجرة',
    'maintenance' => 'صيانة',
    'sold' => 'سجل قديم مغلق',
    _ => value,
  };

  @override
  Widget build(BuildContext context) {
    final available = _equipment.where((e) => e['status'] == 'available').length;
    final rented = _equipment.where((e) => e['status'] == 'rented').length;
    final maintenance = _equipment.where((e) => e['status'] == 'maintenance').length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('المعدات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة معدة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.cream,
                      child: Icon(Icons.handyman_outlined, color: AppColors.navy2),
                    ),
                    title: Text('سجل المعدات فقط',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(
                      'التأجير وعروض الأسعار والفواتير تتم من مركز العمليات. '
                      'لا توجد عملية بيع معدات في هذا القسم.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('إجمالي ${_equipment.length}')),
                    Chip(label: Text('متاحة $available')),
                    Chip(label: Text('مؤجرة $rented')),
                    Chip(label: Text('صيانة $maintenance')),
                  ],
                ),
                const SizedBox(height: 14),
                if (_equipment.isEmpty)
                  const Card(child: ListTile(
                    title: Text('لا توجد معدات بعد'),
                    subtitle: Text('أضف أول معدة من الزر أسفل الشاشة.'),
                  )),
                for (final item in _equipment)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.gold.withValues(alpha: .16),
                              child: const Icon(Icons.precision_manufacturing_outlined,
                                color: AppColors.navy2),
                            ),
                            title: Text('${item['name']} • ${item['code']}',
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text(
                              [
                                if ((item['brand'] as String?)?.isNotEmpty == true)
                                  item['brand'],
                                if ((item['model'] as String?)?.isNotEmpty == true)
                                  item['model'],
                                if (item['manufacture_year'] != null)
                                  'سنة ${item['manufacture_year']}',
                                if ((item['location'] as String?)?.isNotEmpty == true)
                                  'الموقع ${item['location']}',
                                'الحالة ${_status(item['status'] as String)}',
                              ].whereType<Object>().join(' • '),
                            ),
                            trailing: IconButton(
                              tooltip: 'تعديل البطاقة',
                              onPressed: () => _openEditor(item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'مسلسل: ${item['serial_number'] ?? '-'} • '
                                'ساعات: ${((item['meter_hours'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}\n'
                                'مرجعي: ساعة ${_money(item['hourly_rate'])} • '
                                'يوم ${_money(item['daily_rate'])} • '
                                'أسبوع ${_money(item['weekly_rate'])} • '
                                'شهر ${_money(item['monthly_rate'])} • '
                                'سنة ${_money(item['yearly_rate'])}',
                                style: const TextStyle(
                                  color: AppColors.muted, height: 1.5),
                              ),
                            ),
                          ),
                          ButtonBar(
                            children: [
                              TextButton.icon(
                                onPressed: item['status'] == 'rented' ||
                                        item['status'] == 'sold'
                                    ? null
                                    : () => _toggleMaintenance(item),
                                icon: Icon(item['status'] == 'maintenance'
                                    ? Icons.check_circle_outline
                                    : Icons.build_outlined),
                                label: Text(item['status'] == 'maintenance'
                                    ? 'إنهاء الصيانة'
                                    : 'تحويل للصيانة'),
                              ),
                              TextButton.icon(
                                onPressed: () => _openEditor(item),
                                icon: const Icon(Icons.manage_accounts_outlined),
                                label: const Text('التفاصيل والأسعار'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 90),
              ],
            ),
    );
  }

  static String _money(Object? value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
    ),
  );
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: 'إيجار $label المقترح'),
  );
}
