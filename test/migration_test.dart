import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/db/app_database.dart';
import 'package:toy_piecework/data/db/schema.dart';
import 'package:toy_piecework/data/repositories/settlement_repository.dart';

/// 数据库迁移测试（v1 / v2 → 最新版）。
///
/// 这是整个改动里**最危险的一步**：车间手机上已经记了几个月账，
/// 升级时如果加列失败或回填出错，就是实打实的对不上账。
/// 所以这里手工造真正的 v1 / v2 库，再用最新版打开，逐项核对。
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

  test('v1 库升级到最新版：数据一条不少，金额一分不差', () async {
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

    // 8) v3：调整项加了工时/时薪，老数据一律按「直接填金额」处理
    final adjustment = adjustments.single;
    expect(adjustment['work_minutes'], 0);
    expect(adjustment['hourly_rate_cents'], 0);
    expect(adjustment['amount_cents'], 2000, reason: '金额一分不动');

    // 9) v3：工序表已建好并灌入预置项
    final presets = await appDb.raw.query('process_presets');
    expect(presets.length, Defaults.builtinProcesses.length);
    expect(
      presets.map((row) => row['name']),
      contains(Defaults.defaultProcess),
    );

    // 10) v4：联系方式选填，老档案补空串；结算表为空（历史一律未结算）
    final worker = (await appDb.raw.query('workers')).single;
    expect(worker['phone'], '');
    expect(worker['id_card'], '');
    expect(await appDb.raw.query('settlement_marks'), isEmpty);
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

  test('全新安装直接建成最新版，不需要迁移', () async {
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

    // 全新安装也必须有预置工序，否则第一次建档案就是空列表
    final presets = await appDb.raw.query('process_presets');
    expect(presets.length, Defaults.builtinProcesses.length);

    final adjustmentColumns =
        await appDb.raw.rawQuery('PRAGMA table_info(adjustments)');
    expect(
      adjustmentColumns.map((c) => c['name']),
      containsAll(<String>['work_minutes', 'hourly_rate_cents']),
    );

    // v4：工人档案带联系方式，结算标记表已就位
    final workerColumns = await appDb.raw.rawQuery('PRAGMA table_info(workers)');
    expect(
      workerColumns.map((c) => c['name']),
      containsAll(<String>['phone', 'id_card']),
    );
    final markColumns = await appDb.raw.rawQuery(
      'PRAGMA table_info(settlement_marks)',
    );
    expect(
      markColumns.map((c) => c['name']),
      containsAll(<String>['worker_id', 'month', 'is_settled']),
    );
  });

  test('v2 库升级到 v3：以前的工序名自动沉淀成可选的自定义项', () async {
    // 造一个真正的 v2 库：v1 建表 + v2 的加列语句
    final v2 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          for (final statement in v1Statements) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV1ToV2) {
            await db.execute(statement);
          }
        },
      ),
    );

    await v2.insert('workers', {
      'id': 'w1',
      'code': 'W001',
      'name': '张三',
      'pinyin_initials': 'ZS',
      'is_archived': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    // 手打过一个不在预置列表里的工序
    await v2.insert('toys', {
      'id': 't1',
      'name': '小熊',
      'process': '打眼',
      'unit_price_ten_thousandth': 2000,
      'overtime_price_ten_thousandth': 0,
      'pinyin_initials': 'XX',
      'is_archived': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await v2.insert('adjustments', {
      'id': 'a1',
      'date': '2026-06-10',
      'minute_of_day': 600,
      'worker_id': 'w1',
      'worker_name_snapshot': '张三',
      'type': 'bonus',
      'amount_cents': 2000,
      'remark': '全勤',
      'created_at': 1,
      'updated_at': 1,
    });
    await v2.close();

    final appDb = await AppDatabase.open(
      path: dbPath,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    expect(await appDb.raw.getVersion(), Schema.version);

    // 预置项齐全 + 手打过的「打眼」被导入为自定义项
    final presets = await appDb.raw.query('process_presets');
    final names = presets.map((row) => row['name'] as String).toList();
    expect(names.length, Defaults.builtinProcesses.length + 1);
    expect(names, contains('打眼'));
    final custom = presets.firstWhere((row) => row['name'] == '打眼');
    expect(custom['is_builtin'], 0);

    // 老调整项金额不动，新列默认 0
    final adjustment = (await appDb.raw.query('adjustments')).single;
    expect(adjustment['amount_cents'], 2000);
    expect(adjustment['work_minutes'], 0);
    expect(adjustment['hourly_rate_cents'], 0);
    expect(adjustment['minute_of_day'], 600, reason: 'v2 已回填的时间不能被覆盖');

    // 迁移后能直接按工时记一笔新的计时工资
    await appDb.raw.insert('adjustments', {
      'id': 'a2',
      'date': '2026-06-11',
      'minute_of_day': 1200,
      'worker_id': 'w1',
      'worker_name_snapshot': '张三',
      'type': 'hourly',
      'amount_cents': 8750,
      'work_minutes': 210,
      'hourly_rate_cents': 2500,
      'remark': '打包',
      'created_at': 2,
      'updated_at': 2,
    });
    final hourly = (await appDb.raw.query(
      'adjustments',
      where: 'id = ?',
      whereArgs: ['a2'],
    )).single;
    expect(hourly['work_minutes'], 210);
    expect(hourly['hourly_rate_cents'], 2500);
  });

  test('v3 库升级到 v4：老工人没有电话/身份证，账目与标记都不受影响', () async {
    final v3Path = p.join(tempDir.path, 'v3.db');
    final v3 = await databaseFactoryFfi.openDatabase(
      v3Path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          for (final statement in v1Statements) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV1ToV2) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV2ToV3) {
            await db.execute(statement);
          }
        },
      ),
    );
    await v3.insert('workers', {
      'id': 'w1',
      'code': 'W001',
      'name': '张三',
      'pinyin_initials': 'ZS',
      'is_archived': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await v3.insert('piece_records', {
      'id': 'r1',
      'date': '2026-06-10',
      'minute_of_day': 600,
      'worker_id': 'w1',
      'toy_id': 't1',
      'worker_name_snapshot': '张三',
      'toy_name_snapshot': '小熊',
      'process_snapshot': '整件',
      'unit_price_snapshot': 2000,
      'quantity': 100,
      'subtotal_cents': 2000,
      'remark': '',
      'created_at': 1,
      'updated_at': 1,
    });
    await v3.close();

    final appDb = await AppDatabase.open(
      path: v3Path,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    expect(await appDb.raw.getVersion(), Schema.version);

    final worker = (await appDb.raw.query('workers')).single;
    expect(worker['phone'], '', reason: '老档案电话为空，界面显示「未填写」');
    expect(worker['id_card'], '');
    expect(worker['name'], '张三');

    final record = (await appDb.raw.query('piece_records')).single;
    expect(record['subtotal_cents'], 2000, reason: '升级不动金额');

    // 历史账目不能被自动标成已结算
    expect(await appDb.raw.query('settlement_marks'), isEmpty);

    // 迁移后能直接写联系方式与结算标记
    await appDb.raw.update(
      'workers',
      {'phone': '13800001111'},
      where: 'id = ?',
      whereArgs: ['w1'],
    );
    await appDb.raw.insert('settlement_marks', {
      'worker_id': 'w1',
      'month': '2026-06',
      'is_settled': 1,
      'settled_at': 2,
      'updated_at': 2,
    });
    expect(
      (await appDb.raw.query('workers')).single['phone'],
      '13800001111',
    );
    expect((await appDb.raw.query('settlement_marks')).length, 1);
  });

  test('v4 库升级到 v5：加了单笔结算列，老账仍按整月标记结算', () async {
    final v4Path = p.join(tempDir.path, 'v4.db');
    final v4 = await databaseFactoryFfi.openDatabase(
      v4Path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          for (final statement in v1Statements) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV1ToV2) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV2ToV3) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV3ToV4) {
            await db.execute(statement);
          }
        },
      ),
    );
    await v4.insert('workers', {
      'id': 'w1',
      'code': 'W001',
      'name': '张三',
      'phone': '',
      'id_card': '',
      'pinyin_initials': 'ZS',
      'is_archived': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await v4.insert('piece_records', {
      'id': 'r1',
      'date': '2026-06-10',
      'minute_of_day': 600,
      'worker_id': 'w1',
      'toy_id': 't1',
      'worker_name_snapshot': '张三',
      'toy_name_snapshot': '小熊',
      'process_snapshot': '整件',
      'unit_price_snapshot': 2000,
      'quantity': 100,
      'subtotal_cents': 2000,
      'remark': '',
      'created_at': 1,
      'updated_at': 1,
    });
    // v4 时代只有"人 + 月"标记
    await v4.insert('settlement_marks', {
      'worker_id': 'w1',
      'month': '2026-06',
      'is_settled': 1,
      'settled_at': 2,
      'updated_at': 2,
    });
    await v4.close();

    final appDb = await AppDatabase.open(
      path: v4Path,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    expect(await appDb.raw.getVersion(), Schema.version);

    final record = (await appDb.raw.query('piece_records')).single;
    expect(record['subtotal_cents'], 2000, reason: '升级不动金额');
    expect(
      record['settled_at'],
      isNull,
      reason: '老账没有单笔标记，应跟随整月标记而不是凭空写上时间',
    );

    // 整月标记仍然有效：升级后这个月依旧算已结算
    final settlements = SettlementRepository(appDb);
    final worker = (await settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settlementStatus.label, '已结算');
    expect(worker.settledCents, 2000);

    // 新列可写：单笔标记生效后取消整月标记，这笔仍是已结算
    await appDb.raw.update(
      'piece_records',
      {'settled_at': 3},
      where: 'id = ?',
      whereArgs: ['r1'],
    );
    await appDb.raw.delete('settlement_marks');
    final after = (await settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(after.settlementStatus.label, '已结算');
  });

  test('v5 库升级到 v6：新增历史表为空，老账状态与金额一分不变', () async {
    final v5Path = p.join(tempDir.path, 'v5.db');
    final v5 = await databaseFactoryFfi.openDatabase(
      v5Path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) async {
          for (final statement in v1Statements) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV1ToV2) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV2ToV3) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV3ToV4) {
            await db.execute(statement);
          }
          for (final statement in Schema.migrateV4ToV5) {
            await db.execute(statement);
          }
        },
      ),
    );
    await v5.insert('workers', {
      'id': 'w1',
      'code': 'W001',
      'name': '张三',
      'phone': '',
      'id_card': '',
      'pinyin_initials': 'ZS',
      'is_archived': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await v5.insert('piece_records', {
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
      'created_at': 1,
      'updated_at': 1,
    });
    await v5.insert('settlement_marks', {
      'worker_id': 'w1',
      'month': '2026-06',
      'is_settled': 1,
      'settled_at': 2,
      'updated_at': 2,
    });
    await v5.close();

    final appDb = await AppDatabase.open(
      path: v5Path,
      factoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => appDb.close());

    expect(await appDb.raw.getVersion(), Schema.version);
    final columns = await appDb.raw.rawQuery(
      'PRAGMA table_info(settlement_history)',
    );
    expect(columns.map((c) => c['name']), containsAll(<String>[
      'seq',
      'worker_id',
      'action',
      'scope',
      'reason',
      'occurred_at',
      'happened_at',
    ]));
    // 升级前的操作没有留痕，绝不编造历史
    expect(await appDb.raw.query('settlement_history'), isEmpty);

    final record = (await appDb.raw.query('piece_records')).single;
    expect(record['subtotal_cents'], 2000, reason: '升级不动金额');
    expect(record['settled_at'], isNull);
    final settled = (await SettlementRepository(appDb)
            .settle(DateRange.of('2026-06-01', '2026-06-30')))
        .workers
        .single;
    expect(settled.settlementStatus.label, '已结算',
        reason: '整月标记仍然有效');

    // 新表可写，且 seq 从 1 开始作为追加标识
    await appDb.raw.insert('settlement_history', {
      'worker_id': 'w1',
      'action': 'settled',
      'scope': 'range',
      'reason': '',
      'months': '2026-06',
      'range_start': '2026-06-01',
      'range_end': '2026-06-30',
      'entry_label': '',
      'occurred_at': 123,
      'happened_at': '2026-06-10 08:00:00',
    });
    expect((await appDb.raw.query('settlement_history')).single['seq'], 1);
  });
}
