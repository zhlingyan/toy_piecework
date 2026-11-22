import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// 数据库入口：负责打开、建表、事务包装。
///
/// 所有写入路径统一走 [transaction]，恢复账本时整体失败即整体回滚。
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// 只读/简单查询用；写操作请走 [transaction]。
  Database get raw => _db;

  String get path => _db.path;

  static const String fileName = 'toy_piecework.db';

  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factoryOverride,
  }) async {
    final factory = factoryOverride ?? databaseFactory;
    final dbPath = path ?? p.join(await factory.getDatabasesPath(), fileName);
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: Schema.version,
        onConfigure: (db) async {
          try {
            await db.execute('PRAGMA journal_mode = WAL');
          } catch (_) {
            // 内存库或某些平台不支持 WAL，忽略即可。
          }
        },
        onCreate: (db, version) async {
          for (final statement in Schema.createStatements) {
            await db.execute(statement);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // 升级必须在一个事务里完成：任一步失败就整体回滚，
          // 保证不会留下「加了一半列」的半残账本。
          await db.transaction((txn) async {
            if (oldVersion < 2) {
              for (final statement in Schema.migrateV1ToV2) {
                await txn.execute(statement);
              }
            }
          });
        },
      ),
    );
    return AppDatabase._(db);
  }

  /// 测试专用：内存库，进程结束即销毁。
  static Future<AppDatabase> openInMemory({
    DatabaseFactory? factoryOverride,
  }) =>
      open(path: inMemoryDatabasePath, factoryOverride: factoryOverride);

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _db.transaction<T>(action);

  Future<void> close() => _db.close();
}
