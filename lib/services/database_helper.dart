import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static bool _ffiInitialized = false;

  /// On desktop (Windows/Linux/macOS) the default sqflite plugin has no native
  /// implementation, so we route through the FFI factory backed by the bundled
  /// SQLite library. Android and iOS keep the standard plugin.
  static void _ensureDesktopFactory() {
    if (_ffiInitialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _ensureDesktopFactory();
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'buildify.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE projects ADD COLUMN live_url TEXT');
      await db.execute(
        "ALTER TABLE projects ADD COLUMN live_url_status TEXT NOT NULL DEFAULT 'Stopped'",
      );
      await db.execute('UPDATE projects SET subdomain = NULL');
      await db.execute(
        'CREATE UNIQUE INDEX projects_subdomain_unique ON projects(subdomain)',
      );
    }
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE projects ADD COLUMN branch TEXT DEFAULT \'main\'',
      );
      await db.execute('ALTER TABLE projects ADD COLUMN build_command TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN publish_dir TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN base_dir TEXT');
    }
    if (oldVersion < 3) {
      await _createAuthTables(db);
    }
  }

  Future<void> _createAuthTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT UNIQUE,
        phone TEXT UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        auth_method TEXT NOT NULL,
        email_verified INTEGER NOT NULL DEFAULT 0,
        phone_verified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS verification_challenges (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        channel TEXT NOT NULL,
        target TEXT NOT NULL,
        secret_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER,
        attempts INTEGER NOT NULL DEFAULT 0,
        max_attempts INTEGER NOT NULL DEFAULT 5,
        resend_count INTEGER NOT NULL DEFAULT 0,
        last_sent_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        hosting_mode TEXT NOT NULL,
        source_uri TEXT NOT NULL,
        local_path TEXT NOT NULL,
        port INTEGER NOT NULL,
        subdomain TEXT,
        live_url TEXT,
        live_url_status TEXT NOT NULL DEFAULT 'Stopped',
        env_vars TEXT,
        branch TEXT DEFAULT 'main',
        build_command TEXT,
        publish_dir TEXT,
        base_dir TEXT,
        desired_state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_active_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX projects_subdomain_unique ON projects(subdomain)',
    );
    await db.execute('''
      CREATE TABLE deployments (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        commit_hash TEXT,
        status TEXT NOT NULL,
        log_file_path TEXT,
        started_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');

    await _createAuthTables(db);
  }

  // Project CRUD operations
  Future<int> insertProject(Map<String, dynamic> project) async {
    final db = await database;
    return await db.insert(
      'projects',
      project,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Map<String, dynamic>>> getProjects() async {
    final db = await database;
    return await db.query('projects', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getProject(String id) async {
    final db = await database;
    final results = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<int> updateProject(String id, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update(
      'projects',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProject(String id) async {
    final db = await database;
    return await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // Deployment CRUD operations
  Future<int> insertDeployment(Map<String, dynamic> deployment) async {
    final db = await database;
    return await db.insert(
      'deployments',
      deployment,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDeployments(String projectId) async {
    final db = await database;
    return await db.query(
      'deployments',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'started_at DESC',
    );
  }

  // User CRUD operations
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    return await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<Map<String, dynamic>?> getUserById(String id) async {
    final db = await database;
    final results = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'LOWER(email) = LOWER(?)',
      whereArgs: [email.trim()],
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'phone = ?',
      whereArgs: [phone.trim()],
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<Map<String, dynamic>?> getUserByIdentifier(String identifier) async {
    final db = await database;
    final trimmed = identifier.trim();
    final results = await db.query(
      'users',
      where: 'LOWER(email) = LOWER(?) OR phone = ? OR LOWER(name) = LOWER(?)',
      whereArgs: [trimmed, trimmed, trimmed],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<int> updateUser(String id, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update('users', updates, where: 'id = ?', whereArgs: [id]);
  }

  // Verification Challenge operations
  Future<int> insertChallenge(Map<String, dynamic> challenge) async {
    final db = await database;
    return await db.insert('verification_challenges', challenge, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getChallenge(String id) async {
    final db = await database;
    final results = await db.query('verification_challenges', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<List<Map<String, dynamic>>> getActiveChallengesForUser(String userId, String channel) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.query(
      'verification_challenges',
      where: 'user_id = ? AND channel = ? AND consumed_at IS NULL AND expires_at > ?',
      whereArgs: [userId, channel, now],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getActiveChallengesByTarget(String target, String channel) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.query(
      'verification_challenges',
      where: 'target = ? AND channel = ? AND consumed_at IS NULL AND expires_at > ?',
      whereArgs: [target, channel, now],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> updateChallenge(String id, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update('verification_challenges', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('verification_challenges');
    await db.delete('users');
    await db.delete('deployments');
    await db.delete('projects');
  }
}
