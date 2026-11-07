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
      version: 4,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _createBaseSchema(database);
        await _createOperationalSchema(database);
        await _createEquipmentSchema(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createOperationalSchema(database);
        }
        if (oldVersion < 3) {
          await _createEquipmentSchema(database);
          await _ensureNewRentalAccounts(database);
        } else if (oldVersion < 4) {
          await _upgradeEquipmentPricing(database);
        }
      },
    );
    _database = db;
    return db;
  }

  Future<void> _createEquipmentSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rental_equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        serial_number TEXT,
        daily_rate REAL NOT NULL DEFAULT 0 CHECK(daily_rate >= 0),
        hourly_rate REAL NOT NULL DEFAULT 0 CHECK(hourly_rate >= 0),
        weekly_rate REAL NOT NULL DEFAULT 0 CHECK(weekly_rate >= 0),
        monthly_rate REAL NOT NULL DEFAULT 0 CHECK(monthly_rate >= 0),
        yearly_rate REAL NOT NULL DEFAULT 0 CHECK(yearly_rate >= 0),
        purchase_price REAL NOT NULL DEFAULT 0 CHECK(purchase_price >= 0),
        catalog_item_id INTEGER REFERENCES items(id),
        sale_price REAL NOT NULL DEFAULT 0 CHECK(sale_price >= 0),
        status TEXT NOT NULL DEFAULT 'available'
          CHECK(status IN ('available','rented','maintenance','sold')),
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS equipment_rentals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        equipment_id INTEGER NOT NULL REFERENCES rental_equipment(id),
        customer_id INTEGER NOT NULL REFERENCES parties(id),
        document_id INTEGER NOT NULL UNIQUE REFERENCES documents(id),
        start_at TEXT NOT NULL,
        due_at TEXT NOT NULL,
        billing_unit TEXT NOT NULL DEFAULT 'legacy',
        billing_quantity INTEGER NOT NULL DEFAULT 1,
        billing_rate REAL NOT NULL DEFAULT 0,
        earned_amount REAL NOT NULL DEFAULT 0,
        returned_at TEXT,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK(status IN ('active','returned')),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_equipment_rentals_equipment ON equipment_rentals(equipment_id,status)');
  }

  /// All historic rentals remain "legacy": they were previously recognized
  /// in full on creation and must not be accrued for a second time.
  Future<void> _upgradeEquipmentPricing(DatabaseExecutor db) async {
    const columns = <String>[
      'ALTER TABLE rental_equipment ADD COLUMN hourly_rate REAL NOT NULL DEFAULT 0',
      'ALTER TABLE rental_equipment ADD COLUMN weekly_rate REAL NOT NULL DEFAULT 0',
      'ALTER TABLE rental_equipment ADD COLUMN monthly_rate REAL NOT NULL DEFAULT 0',
      'ALTER TABLE rental_equipment ADD COLUMN yearly_rate REAL NOT NULL DEFAULT 0',
      'ALTER TABLE rental_equipment ADD COLUMN purchase_price REAL NOT NULL DEFAULT 0',
      'ALTER TABLE rental_equipment ADD COLUMN catalog_item_id INTEGER REFERENCES items(id)',
      "ALTER TABLE equipment_rentals ADD COLUMN billing_unit TEXT NOT NULL DEFAULT 'legacy'",
      'ALTER TABLE equipment_rentals ADD COLUMN billing_quantity INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE equipment_rentals ADD COLUMN billing_rate REAL NOT NULL DEFAULT 0',
      'ALTER TABLE equipment_rentals ADD COLUMN earned_amount REAL NOT NULL DEFAULT 0',
    ];
    for (final statement in columns) {
      await db.execute(statement);
    }
    await _ensureNewRentalAccounts(db);
  }

  Future<void> _ensureNewRentalAccounts(DatabaseExecutor db) async {
    for (final account in StandardChartOfAccounts.accounts) {
      if (account.code == '2106' || account.code == '4104') {
        await db.insert('accounts', account.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<void> _createBaseSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        code TEXT PRIMARY KEY,
        name_ar TEXT NOT NULL,
        type TEXT NOT NULL,
        level INTEGER NOT NULL,
        is_posting INTEGER NOT NULL CHECK(is_posting IN (0, 1)),
        parent_code TEXT NULL REFERENCES accounts(code)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_sequences (
        document_type TEXT PRIMARY KEY,
        next_number INTEGER NOT NULL DEFAULT 1
      )
    ''');

    final existing = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM accounts'),
        ) ??
        0;
    if (existing == 0) {
      for (final account in StandardChartOfAccounts.accounts) {
        await db.insert('accounts', account.toMap());
      }
    }

    const sequenceTypes = [
      'sales_invoice',
      'purchase_invoice',
      'quotation',
      'receipt_voucher',
      'payment_voucher',
      'journal_entry',
      'financial_claim',
      'official_letter',
      'payroll',
      'equipment_rental',
    ];
    for (final type in sequenceTypes) {
      await db.insert(
        'document_sequences',
        {'document_type': type, 'next_number': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _createOperationalSchema(DatabaseExecutor db) async {
    await _createBaseSchema(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(type IN ('customer','supplier')),
        name TEXT NOT NULL,
        vat_number TEXT,
        commercial_registration TEXT,
        phone TEXT,
        credit_limit REAL NOT NULL DEFAULT 0,
        opening_balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        barcode TEXT UNIQUE,
        name TEXT NOT NULL,
        purchase_price REAL NOT NULL DEFAULT 0,
        sale_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        reorder_level REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        number TEXT NOT NULL UNIQUE,
        date TEXT NOT NULL,
        party_id INTEGER,
        party_name TEXT,
        party_vat_number TEXT,
        party_commercial_registration TEXT,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        status TEXT NOT NULL DEFAULT 'approved',
        subtotal REAL NOT NULL DEFAULT 0,
        vat_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        currency_code TEXT NOT NULL,
        linked_document_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(party_id) REFERENCES parties(id),
        FOREIGN KEY(linked_document_id) REFERENCES documents(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        item_id INTEGER,
        description TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        vat_rate REAL NOT NULL DEFAULT 0,
        line_net REAL NOT NULL,
        line_vat REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
        FOREIGN KEY(item_id) REFERENCES items(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        account_code TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        memo TEXT,
        FOREIGN KEY(entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE,
        FOREIGN KEY(account_code) REFERENCES accounts(code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS party_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        reference TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        document_id INTEGER,
        FOREIGN KEY(party_id) REFERENCES parties(id),
        FOREIGN KEY(document_id) REFERENCES documents(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        value REAL NOT NULL,
        purchase_date TEXT NOT NULL,
        annual_depreciation_rate REAL NOT NULL DEFAULT 0,
        depreciation_account TEXT NOT NULL DEFAULT '5206',
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        basic_salary REAL NOT NULL DEFAULT 0,
        allowances REAL NOT NULL DEFAULT 0,
        advances REAL NOT NULL DEFAULT 0,
        deductions REAL NOT NULL DEFAULT 0,
        overtime REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custody (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('cash','asset')),
        description TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'issued',
        issued_at TEXT NOT NULL,
        FOREIGN KEY(employee_id) REFERENCES employees(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month_key TEXT NOT NULL UNIQUE,
        gross REAL NOT NULL,
        deductions REAL NOT NULL,
        net REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        login_code TEXT NOT NULL UNIQUE,
        pin_hash TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        is_system_admin INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_permissions (
        user_id INTEGER NOT NULL,
        module TEXT NOT NULL,
        can_view INTEGER NOT NULL DEFAULT 0,
        can_add INTEGER NOT NULL DEFAULT 0,
        can_edit INTEGER NOT NULL DEFAULT 0,
        can_delete INTEGER NOT NULL DEFAULT 0,
        can_approve INTEGER NOT NULL DEFAULT 0,
        can_print INTEGER NOT NULL DEFAULT 0,
        can_view_profit INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(user_id, module),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_type_date ON documents(type, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_party_movements_party_date ON party_movements(party_id, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_code)',
    );
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
        await txn.insert(
          'document_sequences',
          {'document_type': documentType, 'next_number': 2},
        );
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
      if (decoded is! Map<String, dynamic>) {
        return LicensePolicy.lockedDefault;
      }
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

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value'] as String?;
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) await db.close();
  }
}
