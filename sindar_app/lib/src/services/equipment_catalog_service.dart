import '../data/local/sindar_database.dart';

class EquipmentCatalogService {
  const EquipmentCatalogService();

  Future<List<Map<String, Object?>>> list() async {
    final db = await SindarDatabase.instance.database;
    return db.query('rental_equipment', orderBy: 'name, code');
  }

  Future<int> add({
    required String code,
    required String name,
    String? serialNumber,
    String? brand,
    String? model,
    int? manufactureYear,
    String? location,
    double meterHours = 0,
    String? conditionNotes,
    String? notes,
    double purchaseCost = 0,
    double marketValue = 0,
    double hourlyRate = 0,
    double dailyRate = 0,
    double weeklyRate = 0,
    double monthlyRate = 0,
    double yearlyRate = 0,
  }) async {
    _validate(
      code: code,
      name: name,
      manufactureYear: manufactureYear,
      meterHours: meterHours,
      values: [
        purchaseCost, marketValue, hourlyRate, dailyRate,
        weeklyRate, monthlyRate, yearlyRate,
      ],
    );
    final db = await SindarDatabase.instance.database;
    return db.insert('rental_equipment', {
      'code': code.trim(),
      'name': name.trim(),
      'serial_number': _nullIfEmpty(serialNumber),
      'brand': _nullIfEmpty(brand),
      'model': _nullIfEmpty(model),
      'manufacture_year': manufactureYear,
      'location': _nullIfEmpty(location),
      'meter_hours': meterHours,
      'condition_notes': _nullIfEmpty(conditionNotes),
      'notes': _nullIfEmpty(notes),
      'purchase_price': purchaseCost,
      'sale_price': marketValue,
      'hourly_rate': hourlyRate,
      'daily_rate': dailyRate,
      'weekly_rate': weeklyRate,
      'monthly_rate': monthlyRate,
      'yearly_rate': yearlyRate,
      'status': 'available',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> update({
    required int id,
    required String code,
    required String name,
    String? serialNumber,
    String? brand,
    String? model,
    int? manufactureYear,
    String? location,
    double meterHours = 0,
    String? conditionNotes,
    String? notes,
    double purchaseCost = 0,
    double marketValue = 0,
    double hourlyRate = 0,
    double dailyRate = 0,
    double weeklyRate = 0,
    double monthlyRate = 0,
    double yearlyRate = 0,
  }) async {
    _validate(
      code: code,
      name: name,
      manufactureYear: manufactureYear,
      meterHours: meterHours,
      values: [
        purchaseCost, marketValue, hourlyRate, dailyRate,
        weeklyRate, monthlyRate, yearlyRate,
      ],
    );
    final db = await SindarDatabase.instance.database;
    final changed = await db.update('rental_equipment', {
      'code': code.trim(),
      'name': name.trim(),
      'serial_number': _nullIfEmpty(serialNumber),
      'brand': _nullIfEmpty(brand),
      'model': _nullIfEmpty(model),
      'manufacture_year': manufactureYear,
      'location': _nullIfEmpty(location),
      'meter_hours': meterHours,
      'condition_notes': _nullIfEmpty(conditionNotes),
      'notes': _nullIfEmpty(notes),
      'purchase_price': purchaseCost,
      'sale_price': marketValue,
      'hourly_rate': hourlyRate,
      'daily_rate': dailyRate,
      'weekly_rate': weeklyRate,
      'monthly_rate': monthlyRate,
      'yearly_rate': yearlyRate,
    }, where: 'id=?', whereArgs: [id]);
    if (changed != 1) throw const FormatException('المعدة غير موجودة');
  }

  Future<void> setMaintenance(int id, bool maintenance) async {
    final db = await SindarDatabase.instance.database;
    final rows = await db.query('rental_equipment',
      columns: ['status'], where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const FormatException('المعدة غير موجودة');
    final current = rows.first['status'] as String;
    if (current == 'rented') {
      throw const FormatException('لا يمكن تغيير حالة معدة مؤجرة حالياً');
    }
    if (current == 'sold') {
      throw const FormatException('هذه المعدة مغلقة في بيانات قديمة ولا يمكن تشغيلها');
    }
    await db.update('rental_equipment',
      {'status': maintenance ? 'maintenance' : 'available'},
      where: 'id=?', whereArgs: [id]);
  }

  static void _validate({
    required String code,
    required String name,
    required int? manufactureYear,
    required double meterHours,
    required List<double> values,
  }) {
    if (code.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('رقم المعدة واسمها مطلوبان');
    }
    final nowYear = DateTime.now().year + 1;
    if (manufactureYear != null &&
        (manufactureYear < 1900 || manufactureYear > nowYear)) {
      throw const FormatException('سنة الصنع غير صحيحة');
    }
    if (!meterHours.isFinite || meterHours < 0 ||
        values.any((value) => !value.isFinite || value < 0)) {
      throw const FormatException('القيم والأسعار يجب أن تكون أرقاماً غير سالبة');
    }
  }

  static String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
