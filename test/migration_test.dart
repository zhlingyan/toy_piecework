import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:toy_piecework/data/db/app_database.dart';
import 'package:toy_piecework/data/db/schema.dart';

/// v1 → v2 迁移测试。
///
/// 这是整个改动里**最危险的一步**：车间手机上已经记了几个月账，
/// 升级时如果加列失败或回填出错，就是实打实的对不上账。
/// 所以这里手工造一个真正的 v1 库，再用 v2 打开，逐项核对。
void main() {
  late Directory tempDir;
  late String dbPath;

  // v1 的建表语句，原样保留（刻意不引用 Schema，因为 Schema 已经是 v2）。
  const v1Statements = [
    '''
    CREATE TABLE workers (
      id TEXT PRIMARY KEY NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL,
      pinyin_initials TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE toys (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      process TEXT NOT NULL DEFAULT '整件',
      unit_price_ten_thousandth INTEGER NOT NULL DEFAULT 0,
      pinyin_initials TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE piece_records (
      id TEXT PRIMARY KEY NOT NULL,
      date TEXT NOT NULL,
      worker_id TEXT NOT NULL,
      toy_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      toy_name_snapshot TEXT NOT NULL,
      process_snapshot TEXT NOT NULL,
      unit_price_snapshot INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      subtotal_cents INTEGER NOT NULL,
      remark TEXT NOT NULL DEFAULT '',
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (quantity > 0)
    )
    ''',
    '''
    CREATE TABLE adjustments (
      id TEXT PRIMARY KEY NOT NULL,
      date TEXT NOT NULL,
      worker_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      remark TEXT NOT NULL,
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (amount_cents > 0),
      CHECK (type IN ('bonus','hourly','deduction','advance'))
    )
    ''',
    '''
    CREATE TABLE locked_months (
      month TEXT PRIMARY KEY NOT NULL,
      is_locked INTEGER NOT NULL DEFAULT 0,
      locked_at INTEGER,
      unlocked_at INTEGER
    )
    ''',
    'CREATE INDEX idx_records_date ON piece_records(date)',
    'CREATE INDEX idx_adjustments_date ON adjustments(date)',
  ];

  setUp(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('toy_migrate_test_');
    dbPath = p.join(tempDir.path, 'v1.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 造一个 v1 库并写入旧数据，然后关闭。
  Future<void> createV1Database({required int createdAt}) async {
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          for (final statement in v1Statements) {
            await db.execute(statement);
          }
        },
      ),
    );

    await db.insert('workers', {
      'id': 'w1',
      'code': 'W001',
      'name': '张三',
      'pinyin_initials': 'ZS',
      'is_archived': 0,
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    await db.insert('toys', {
      'id': 't1',
      'name': '小熊',
      'process': '整件',
      'unit_price_ten_thousandth': 2000,
      'pinyin_initials': 'XX',
      'is_archived': 0,
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    // 两笔旧流水，单价不同（模拟调价），合计 45.00 元
    await db.insert('piece_records', {
      'id': 'r1',
      'date': '2026-06-10',
      'worker_id': 'w1',
      'toy_id': 't1',
      'worker_name_snapshot': '张三',
      'toy_name_snapshot': '小熊',
      'process_snapshot': '整件',
      'unit_price_snapshot': 2000,
      'quantity': 100,
      'subtotal_cents': 2000,
      'remark': '',
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    await db.insert('piece_records', {
      'id': 'r2',
      'date': '2026-06-10',
      'worker_id': 'w1',
      'toy_id': 't1',
      'worker_name_snapshot': '张三',
      'toy_name_snapshot': '小熊',
      'process_snapshot': '整件',
      'unit_price_snapshot': 2500,
      'quantity': 100,
      'subtotal_cents': 2500,
      'remark': '',
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    await db.insert('adjustments', {
      'id': 'a1',
      'date': '2026-06-10',
      'worker_id': 'w1',
      'worker_name_snapshot': '张三',
      'type': 'bonus',
      'amount_cents': 2000,
      'remark': '全勤',
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    await db.close();
  }

  test('v1 库升级到 v2：数据一条不少，金额一分不差', () async {
    // 2026-06-10 15:42 本地时间
    final localTime = DateTime(2026, 6, 10, 15, 42);
    await createV1Database(createdAt: localTime.millisecondsSinceEpoch);

    final appDb = await AppDatabase.open(
      path: dbPath,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    final version = await appDb.raw.getVersion();
    expect(version, Schema.version, reason: '应升到最新版本');

    // 1) 数据量不变
    final records = await appDb.raw.query('piece_records');
    expect(records.length, 2);
    expect((await appDb.raw.query('workers')).length, 1);
    expect((await appDb.raw.query('adjustments')).length, 1);

    // 2) 金额一分不差（这是最关键的断言）
    final subtotals = records.map((r) => r['subtotal_cents'] as int).toList()
      ..sort();
    expect(subtotals, [2000, 2500]);

    // 3) 新列已存在且默认值正确
    for (final row in records) {
      expect(row['overtime'], 0, reason: '老流水一律视为非加班');
      expect(row['overtime_price_snapshot'], 0);
      expect(row['overtime_multiplier'], 1000);
    }

    // 4) 时间用录入时刻回填：15:42 => 942 分钟
    expect(records.first['minute_of_day'], 15 * 60 + 42);

    // 5) 玩具的加班单价默认为 0（未设置）
    final toys = await appDb.raw.query('toys');
    expect(toys.single['overtime_price_ten_thousandth'], 0);

    // 6) 调整项也有分钟字段
    final adjustments = await appDb.raw.query('adjustments');
    expect(adjustments.single['minute_of_day'], 15 * 60 + 42);

    // 7) 新索引建好了
    final indexes = await appDb.raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_records_date_minute'",
    );
    expect(indexes.length, 1);
  });

  test('升级后老流水写入新字段仍能正常读回', () async {
    final localTime = DateTime(2026, 6, 10, 8, 0);
    await createV1Database(createdAt: localTime.millisecondsSinceEpoch);

    final appDb = await AppDatabase.open(
      path: dbPath,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    // 在迁移后的库里插一条加班流水，验证新列可写、CHECK 未误伤
    await appDb.raw.insert('piece_records', {
      'id': 'r3',
      'date': '2026-06-11',
      'minute_of_day': 1200,
      'worker_id': 'w1',
      'toy_id': 't1',
      'worker_name_snapshot': '张三',
      'toy_name_snapshot': '小熊',
      'process_snapshot': '整件',
      'unit_price_snapshot': 2000,
      'quantity': 10,
      'subtotal_cents': 300,
      'overtime': 1,
      'overtime_price_snapshot': 3000,
      'overtime_multiplier': 1500,
      'remark': '',
      'created_at': localTime.millisecondsSinceEpoch,
      'updated_at': localTime.millisecondsSinceEpoch,
    });

    final rows = await appDb.raw.query(
      'piece_records',
      where: 'id = ?',
      whereArgs: ['r3'],
    );
    expect(rows.single['overtime'], 1);
    expect(rows.single['overtime_price_snapshot'], 3000);
  });

  test('全新安装直接建成 v2，不需要迁移', () async {
    final freshPath = p.join(tempDir.path, 'fresh.db');
    final appDb = await AppDatabase.open(
      path: freshPath,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    expect(await appDb.raw.getVersion(), Schema.version);

    final columns = await appDb.raw.rawQuery(
      'PRAGMA table_info(piece_records)',
    );
    final names = columns.map((c) => c['name'] as String).toSet();
    expect(names, containsAll(<String>[
      'minute_of_day',
      'overtime',
      'overtime_price_snapshot',
      'overtime_multiplier',
    ]));

    final toyColumns = await appDb.raw.rawQuery('PRAGMA table_info(toys)');
    expect(
      toyColumns.map((c) => c['name']),
      contains('overtime_price_ten_thousandth'),
    );
  });
}
