import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sindar_core/sindar_core.dart';
import 'package:sqflite/sqflite.dart';

class SindarDatabase {
  SindarDatabase._();

  static final SindarDatabase instance = SindarDatabase._();

  Database? _database;

  Future<Database> get database async {
    final cached = _database;
    if (cached != null) return cached;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'sindar.db'),
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.transaction((txn) async {
          await txn.execute('''
            CREATE TABLE accounts (
              code TEXT PRIMARY KEY,
              name_ar TEXT NOT NULL,
              type TEXT NOT NULL,
              level INTEGER NOT NULL,
              is_posting INTEGER NOT NULL CHECK(is_posting IN (0, 1)),
              parent_code TEXT NULL REFERENCES accounts(code)
            )
          ''');
          await txn.execute('''
            CREATE TABLE app_settings (
              setting_key TEXT PRIMARY KEY,
              setting_value TEXT NOT NULL
            )
          ''');
          await txn.execute('''
            CREATE TABLE document_sequences (
              document_type TEXT PRIMARY KEY,
              next_number INTEGER NOT NULL DEFAULT 1
            )
          ''');

          for (final account in StandardChartOfAccounts.accounts) {
            await txn.insert('accounts', account.toMap());
          }

          const sequenceTypes = [
            'sales_invoice',
            'purchase_invoice',
            'quotation',
            'receipt_voucher',
            'payment_voucher',
            'journal_entry',
          ];
          for (final type in sequenceTypes) {
            await txn.insert('document_sequences', {
              'document_type': type,
              'next_number': 1,
            });
          }
        });
      },
    );
    _database = db;
    return db;
  }

  Future<List<Account>> getAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'code ASC');
    return rows.map(Account.fromMap).toList(growable: false);
  }

  Future<int> nextDocumentNumber(String documentType) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'document_sequences',
        columns: ['next_number'],
        where: 'document_type = ?',
        whereArgs: [documentType],
        limit: 1,
      );

      if (rows.isEmpty) {
        await txn.insert('document_sequences', {
          'document_type': documentType,
          'next_number': 2,
        });
        return 1;
      }

      final current = rows.first['next_number']! as int;
      await txn.update(
        'document_sequences',
        {'next_number': current + 1},
        where: 'document_type = ?',
        whereArgs: [documentType],
      );
      return current;
    });
  }

  Future<LicensePolicy> getLicensePolicy() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['license_policy'],
      limit: 1,
    );
    if (rows.isEmpty) return LicensePolicy.lockedDefault;

    try {
      final decoded = jsonDecode(rows.first['setting_value']! as String);
      if (decoded is! Map<String, dynamic>) return LicensePolicy.lockedDefault;
      return LicensePolicy.fromJson(decoded);
    } on FormatException {
      return LicensePolicy.lockedDefault;
    }
  }

  Future<void> saveLicensePolicy(LicensePolicy policy) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {
        'setting_key': 'license_policy',
        'setting_value': jsonEncode(policy.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) await db.close();
  }
}
