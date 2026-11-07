// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:path/path.dart' as p;
import 'package:sindar_core/sindar_core.dart';
import 'package:sqflite/sqflite.dart';

class AdminLicenseRecord {
  const AdminLicenseRecord({
    required this.id,
    required this.organizationName,
    required this.licenseNumber,
    required this.expiresAt,
    required this.isActive,
    required this.isTaxEnabled,
    required this.countryCode,
    required this.currencyCode,
    required this.currencySymbol,
    required this.maxAllowedUsers,
    required this.token,
  });

  final int id;
  final String organizationName;
  final String licenseNumber;
  final DateTime expiresAt;
  final bool isActive;
  final bool isTaxEnabled;
  final String countryCode;
  final String currencyCode;
  final String currencySymbol;
  final int maxAllowedUsers;
  final String token;

  factory AdminLicenseRecord.fromMap(Map<String, Object?> row) {
    return AdminLicenseRecord(
      id: row['id']! as int,
      organizationName: row['organization_name']! as String,
      licenseNumber: row['license_number']! as String,
      expiresAt: DateTime.parse(row['expires_at']! as String),
      isActive: (row['is_active']! as int) == 1,
      isTaxEnabled: (row['is_tax_enabled']! as int) == 1,
      countryCode: row['country_code']! as String,
      currencyCode: row['currency_code']! as String,
      currencySymbol: row['currency_symbol']! as String,
      maxAllowedUsers: row['max_allowed_users']! as int,
      token: row['token']! as String,
    );
  }
}

class AdminLicenseStore {
  AdminLicenseStore._();

  static final AdminLicenseStore instance = AdminLicenseStore._();
  static const signingSecret = 'sindar-offline-signing-key-v1';

  Database? _db;

  Future<Database> get database async {
    final cached = _db;
    if (cached != null) return cached;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'sindar_admin.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE licenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            organization_name TEXT NOT NULL,
            license_number TEXT NOT NULL UNIQUE,
            expires_at TEXT NOT NULL,
            is_active INTEGER NOT NULL,
            is_tax_enabled INTEGER NOT NULL,
            country_code TEXT NOT NULL,
            currency_code TEXT NOT NULL,
            currency_symbol TEXT NOT NULL,
            max_allowed_users INTEGER NOT NULL,
            token TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<List<AdminLicenseRecord>> list() async {
    final db = await database;
    final rows = await db.query('licenses', orderBy: 'id DESC');
    final result = <AdminLicenseRecord>[];
    for (final row in rows) {
      var record = AdminLicenseRecord.fromMap(row);
      if (!record.token.startsWith('S2.')) {
        final grant = LicenseGrant(
          organizationName: record.organizationName,
          licenseNumber: record.licenseNumber,
          expiresAt: record.expiresAt.toUtc(),
          isActive: record.isActive,
          policy: LicensePolicy(
            customerId: record.licenseNumber,
            isTaxEnabled: record.isTaxEnabled,
            countryCode: record.countryCode,
            currencyCode: record.currencyCode,
            currencySymbol: record.currencySymbol,
            maxUsers: record.maxAllowedUsers,
          ),
        );
        final compact = LicenseTokenCodec.encode(
          grant: grant,
          signingSecret: signingSecret,
        );
        await db.update(
          'licenses',
          {
            'token': compact,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );
        final updated = Map<String, Object?>.from(row)
          ..['token'] = compact;
        record = AdminLicenseRecord.fromMap(updated);
      }
      result.add(record);
    }
    return result;
  }

  Future<AdminLicenseRecord> save({
    int? id,
    required String organizationName,
    required String licenseNumber,
    required DateTime expiresAt,
    required bool isActive,
    required bool isTaxEnabled,
    required String countryCode,
    required String currencyCode,
    required String currencySymbol,
    required int maxAllowedUsers,
  }) async {
    if (maxAllowedUsers < 1) {
      throw const FormatException('عدد المستخدمين يجب أن يكون 1 على الأقل');
    }
    final grant = LicenseGrant(
      organizationName: organizationName.trim(),
      licenseNumber: licenseNumber.trim(),
      expiresAt: expiresAt.toUtc(),
      isActive: isActive,
      policy: LicensePolicy(
        customerId: licenseNumber.trim(),
        isTaxEnabled: isTaxEnabled,
        countryCode: countryCode,
        currencyCode: currencyCode,
        currencySymbol: currencySymbol,
        maxUsers: maxAllowedUsers,
      ),
    );
    final token = LicenseTokenCodec.encode(
      grant: grant,
      signingSecret: signingSecret,
    );
    final db = await database;
    final values = <String, Object?>{
      'organization_name': organizationName.trim(),
      'license_number': licenseNumber.trim(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'is_tax_enabled': isTaxEnabled ? 1 : 0,
      'country_code': countryCode,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'max_allowed_users': maxAllowedUsers,
      'token': token,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    late final int savedId;
    if (id == null) {
      savedId = await db.insert('licenses', values);
    } else {
      await db.update(
        'licenses',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      savedId = id;
    }
    final rows = await db.query(
      'licenses',
      where: 'id = ?',
      whereArgs: [savedId],
      limit: 1,
    );
    return AdminLicenseRecord.fromMap(rows.first);
  }
}
