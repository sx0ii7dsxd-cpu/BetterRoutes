import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({String? path}) : _databasePath = path;

  static final AppDatabase instance = AppDatabase();

  static const int version = 3;
  static const String databaseName = 'better_routes.db';
  final String? _databasePath;

  Future<Database>? _database;

  Future<Database> get database => _database ??= _openDatabase();

  Future<Database> _openDatabase() async {
    final String path;
    if (_databasePath case final String databasePath) {
      path = databasePath;
    } else {
      final String directory = await getDatabasesPath();
      path = '$directory/$databaseName';
    }

    return openDatabase(
      path,
      version: version,
      onConfigure: (Database database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE warehouses (
        id TEXT PRIMARY KEY NOT NULL,
        warehouse_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        address TEXT NOT NULL CHECK (length(trim(address)) > 0),
        contact_name TEXT NOT NULL CHECK (length(trim(contact_name)) > 0),
        contact_number TEXT NOT NULL CHECK (length(trim(contact_number)) > 0),
        location_note TEXT NOT NULL DEFAULT '',
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (
          (latitude IS NULL AND longitude IS NULL) OR
          (
            latitude IS NOT NULL AND longitude IS NOT NULL AND
            latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180
          )
        )
      )
    ''');
    await database.execute(
      'CREATE INDEX warehouses_name_index ON warehouses(name COLLATE NOCASE)',
    );
    await _createPhaseTwoSchema(database);
    await _createPhaseThreeSchema(database);
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createPhaseTwoSchema(database);
    }
    if (oldVersion < 3) {
      await _createPhaseThreeSchema(database);
    }
  }

  Future<void> _createPhaseTwoSchema(Database database) async {
    await database.execute('''
      CREATE TABLE user_profiles (
        uid TEXT PRIMARY KEY NOT NULL,
        display_name TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        photo_url TEXT NOT NULL DEFAULT '',
        provider_ids TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE businesses (
        id TEXT PRIMARY KEY NOT NULL,
        owner_uid TEXT NOT NULL,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (owner_uid) REFERENCES user_profiles(uid)
          ON DELETE RESTRICT
      )
    ''');
    await database.execute(
      'CREATE INDEX businesses_owner_index ON businesses(owner_uid)',
    );
    await database.execute('''
      CREATE TABLE trucks (
        id TEXT PRIMARY KEY NOT NULL,
        registration_number TEXT NOT NULL COLLATE NOCASE UNIQUE,
        truck_type TEXT NOT NULL CHECK (
          truck_type IN (
            'Mini truck',
            'Box truck',
            'Heavy truck',
            'Refrigerated truck'
          )
        ),
        capacity TEXT NOT NULL CHECK (length(trim(capacity)) > 0),
        details TEXT NOT NULL DEFAULT '',
        driver_name TEXT NOT NULL CHECK (length(trim(driver_name)) > 0),
        driver_contact_number TEXT NOT NULL
          CHECK (length(trim(driver_contact_number)) > 0),
        warehouse_id TEXT NOT NULL,
        business_id TEXT NOT NULL,
        approval_status TEXT NOT NULL DEFAULT 'pending'
          CHECK (approval_status IN ('pending', 'approved', 'rejected')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)
          ON DELETE RESTRICT,
        FOREIGN KEY (business_id) REFERENCES businesses(id)
          ON DELETE RESTRICT
      )
    ''');
    await database.execute(
      'CREATE INDEX trucks_warehouse_index ON trucks(warehouse_id)',
    );
    await database.execute(
      'CREATE INDEX trucks_business_index ON trucks(business_id)',
    );
  }

  Future<void> _createPhaseThreeSchema(Database database) async {
    await database.execute('''
      CREATE TABLE saved_places (
        id TEXT PRIMARY KEY NOT NULL,
        place_key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
        address TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        provider_place_id TEXT,
        saved_at TEXT NOT NULL,
        CHECK (
          latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180
        )
      )
    ''');
    await database.execute(
      'CREATE INDEX saved_places_name_index '
      'ON saved_places(name COLLATE NOCASE)',
    );
    await database.execute('''
      CREATE TABLE recent_searches (
        id TEXT PRIMARY KEY NOT NULL,
        destination_key TEXT NOT NULL UNIQUE,
        query TEXT NOT NULL CHECK (length(trim(query)) > 0),
        place_name TEXT,
        address TEXT,
        latitude REAL,
        longitude REAL,
        provider_place_id TEXT,
        searched_at TEXT NOT NULL,
        CHECK (
          (latitude IS NULL AND longitude IS NULL) OR
          (
            latitude IS NOT NULL AND longitude IS NOT NULL AND
            latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180
          )
        )
      )
    ''');
    await database.execute(
      'CREATE INDEX recent_searches_searched_at_index '
      'ON recent_searches(searched_at DESC)',
    );
  }

  Future<void> close() async {
    final Future<Database>? openingDatabase = _database;
    _database = null;
    if (openingDatabase != null) {
      await (await openingDatabase).close();
    }
  }
}
