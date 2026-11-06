// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import '../data/local/sindar_database.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';

class AssetsAndCustodyScreen extends StatefulWidget {
  const AssetsAndCustodyScreen({super.key});

  @override
  State<AssetsAndCustodyScreen> createState() => _AssetsAndCustodyScreenState();
}

class _AssetsAndCustodyScreenState extends State<AssetsAndCustodyScreen> {
  List<Map<String, Object?>> _assets = const [];
  List<Map<String, Object?>> _employees = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final assets = await ErpRepository.instance.listAssets();
    final employees = await ErpRepository.instance.listEmployees();
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _employees = employees;
      _loading = false;
    });
  }

  Future<void> _addAsset() async {
    final name = TextEditingController();
    final value = TextEditingController();
    final rate = TextEditingController(text: '10');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل أصل ثابت'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الأصل')),
            const SizedBox(height: 8),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'القيمة'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'نسبة الإهلاك السنوي %'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      await ErpRepository.instance.addAsset(
        name: name.text,
        value: double.tryParse(value.text) ?? 0,
        purchaseDate: DateTime.now(),
        annualDepreciationRate: double.tryParse(rate.text) ?? 0,
      );
      await _refresh();
    }
    name.dispose();
    value.dispose();
    rate.dispose();
  }

  Future<void> _addCustody() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف موظفاً أولاً من قسم الموظفين والرواتب')),
      );
      return;
    }
    int? employeeId;
    String kind = 'asset';
    final description = TextEditingController();
    final amount = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('تسليم عهدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: employeeId,
                decoration: const InputDecoration(labelText: 'الموظف'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('اختر الموظف')),
                  for (final employee in _employees)
                    DropdownMenuItem<int?>(
                      value: employee['id']! as int,
                      child: Text(employee['name']! as String),
                    ),
                ],
                onChanged: (value) => setLocalState(() => employeeId = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'نوع العهدة'),
                items: const [
                  DropdownMenuItem(value: 'asset', child: Text('عينية')),
                  DropdownMenuItem(value: 'cash', child: Text('مالية')),
                ],
                onChanged: (value) {
                  if (value != null) setLocalState(() => kind = value);
                },
              ),
              const SizedBox(height: 8),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'القيمة'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تسليم')),
          ],
        ),
      ),
    );
    if (accepted == true && employeeId != null && description.text.trim().isNotEmpty) {
      await ErpRepository.instance.addCustody(
        employeeId: employeeId!,
        kind: kind,
        description: description.text,
        amount: double.tryParse(amount.text) ?? 0,
      );
    }
    description.dispose();
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأصول والعهد'),
        actions: [
          IconButton(
            tooltip: 'تسليم عهدة',
            onPressed: _addCustody,
            icon: const Icon(Icons.badge_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAsset,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('أصل جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _assets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final asset = _assets[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text(asset['name']! as String),
                    subtitle: Text(
                      'القيمة: ' +
                          (asset['value'] as num).toDouble().toStringAsFixed(2) +
                          ' • إهلاك: ' +
                          (asset['annual_depreciation_rate'] as num).toDouble().toStringAsFixed(2) +
                          '%',
                    ),
                    trailing: Text(asset['status']! as String),
                  ),
                );
              },
            ),
    );
  }
}

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  List<Map<String, Object?>> _employees = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rows = await ErpRepository.instance.listEmployees();
    if (!mounted) return;
    setState(() {
      _employees = rows;
      _loading = false;
    });
  }

  Future<void> _addEmployee() async {
    final name = TextEditingController();
    final basic = TextEditingController();
    final allowances = TextEditingController(text: '0');
    final advances = TextEditingController(text: '0');
    final deductions = TextEditingController(text: '0');
    final overtime = TextEditingController(text: '0');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة موظف'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 8),
              TextField(controller: basic, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الراتب الأساسي')),
              const SizedBox(height: 8),
              TextField(controller: allowances, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'البدلات')),
              const SizedBox(height: 8),
              TextField(controller: advances, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السلف')),
              const SizedBox(height: 8),
              TextField(controller: deductions, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الخصومات')),
              const SizedBox(height: 8),
              TextField(controller: overtime, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الإضافي')),
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
      await ErpRepository.instance.addEmployee(
        name: name.text,
        basicSalary: double.tryParse(basic.text) ?? 0,
        allowances: double.tryParse(allowances.text) ?? 0,
        advances: double.tryParse(advances.text) ?? 0,
        deductions: double.tryParse(deductions.text) ?? 0,
        overtime: double.tryParse(overtime.text) ?? 0,
      );
      await _refresh();
    }

    name.dispose();
    basic.dispose();
    allowances.dispose();
    advances.dispose();
    deductions.dispose();
    overtime.dispose();
  }

  Future<void> _runPayroll() async {
    final now = DateTime.now();
    final monthKey =
        now.year.toString() + '-' + now.month.toString().padLeft(2, '0');
    try {
      await ErpRepository.instance.runPayroll(monthKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إصدار وصرف مسير رواتب ' +
                monthKey +
                ' وإنشاء سندات الصرف والقيد المحاسبي',
          ),
        ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفون والرواتب'),
        actions: [
          IconButton(
            tooltip: 'إصدار مسير الشهر',
            onPressed: _employees.isEmpty ? null : _runPayroll,
            icon: const Icon(Icons.payments_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEmployee,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('موظف جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _employees.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final employee = _employees[index];
                final gross =
                    (employee['basic_salary'] as num).toDouble() +
                    (employee['allowances'] as num).toDouble() +
                    (employee['overtime'] as num).toDouble();
                final deductions =
                    (employee['advances'] as num).toDouble() +
                    (employee['deductions'] as num).toDouble();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(employee['name']! as String),
                    subtitle: Text(
                      'إجمالي مستحق: ' +
                          gross.toStringAsFixed(2) +
                          ' • خصومات/سلف: ' +
                          deductions.toStringAsFixed(2),
                    ),
                    trailing: Text(
                      (gross - deductions).toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  FinancialReportSnapshot? _report;
  bool _taxEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final report = await ErpRepository.instance.financialReport();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _report = report;
      _taxEnabled = policy.isTaxEnabled;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير والتحليلات'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading || report == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'قائمة الدخل',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  _MetricTile('صافي المبيعات', report.revenue),
                  _MetricTile('تكلفة المبيعات', report.costOfSales),
                  _MetricTile('المصروفات التشغيلية', report.operatingExpenses),
                  _MetricTile(
                    report.netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                    report.netProfit,
                    emphasized: true,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'الذمم',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  _MetricTile('ديون لنا عند العملاء', report.receivables),
                  _MetricTile('ديون علينا للموردين', report.payables),
                  if (_taxEnabled) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'تقرير ضريبة القيمة المضافة',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    _MetricTile('ضريبة المبيعات', report.salesVat),
                    _MetricTile('ضريبة المشتريات', report.purchaseVat),
                    _MetricTile('صافي الضريبة المستحقة', report.netVat, emphasized: true),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'الصندوق والبنوك',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  _MetricTile('حركة / رصيد الصندوق', report.cashBalance),
                  _MetricTile('حركة / رصيد البنوك', report.bankBalance),
                  const SizedBox(height: 18),
                  const Text(
                    'ميزان المراجعة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الحساب')),
                        DataColumn(label: Text('الاسم')),
                        DataColumn(label: Text('مدين')),
                        DataColumn(label: Text('دائن')),
                      ],
                      rows: [
                        for (final row in report.trialBalance)
                          DataRow(
                            cells: [
                              DataCell(Text(row.code)),
                              DataCell(Text(row.name)),
                              DataCell(Text(row.debit.toStringAsFixed(2))),
                              DataCell(Text(row.credit.toStringAsFixed(2))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
    this.label,
    this.value, {
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: emphasized ? 2 : 0,
      child: ListTile(
        title: Text(label, style: TextStyle(fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700)),
        trailing: Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontSize: emphasized ? 19 : 16,
            fontWeight: FontWeight.w900,
            color: emphasized
                ? (value >= 0 ? Colors.green.shade700 : Colors.red.shade700)
                : null,
          ),
        ),
      ),
    );
  }
}
