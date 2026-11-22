import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';
import 'package:toy_piecework/data/services/backup_service.dart';

import 'support/fixture.dart';

void main() {
  late Fixture source;

  setUp(() async {
    source = await Fixture.create();
  });

  tearDown(() async {
    await source.dispose();
  });

  Future<void> seed(Fixture f) async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(date: '2026-06-01', worker: worker, toy: toy, quantity: 100);
    await f.records.create(date: '2026-06-02', worker: worker, toy: toy, quantity: 50);
    await f.adjustments.create(
      date: '2026-06-02',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤',
    );
    await f.months.lock('2026-05');
  }

  test('导出 → 校验 → 预览：统计与日期跨度正确', () async {
    await seed(source);
    final json = await source.backup.buildJson();
    final preview = source.backup.inspect(json);

    expect(preview.summary.version, Defaults.backupVersion);
    expect(preview.summary.workerCount, 1);
    expect(preview.summary.toyCount, 1);
    expect(preview.summary.recordCount, 2);
    expect(preview.summary.adjustmentCount, 1);
    expect(preview.summary.lockedMonthCount, 1);
    expect(preview.summary.minDate, '2026-06-01');
    expect(preview.summary.maxDate, '2026-06-02');
  });

  test('恢复后数据完整一致', () async {
    await seed(source);
    final json = await source.backup.buildJson();
    final preview = source.backup.inspect(json);

    final target = await Fixture.create();
    addTearDown(target.dispose);

    final result = await target.backup.restore(
      preview,
      persistSafetyBackup: (current) async {
        expect(current.isNotEmpty, isTrue);
        return 'memory://safety.json';
      },
    );
    expect(result.safetyBackupPath, 'memory://safety.json');

    final records = await target.records.listRange(
      DateRange.of('2026-06-01', '2026-06-30'),
    );
    expect(records.length, 2);
    expect(records.every((r) => r.unitPriceSnapshot == 2000), isTrue);
    expect(records.every((r) => r.subtotalCents == 2000 || r.subtotalCents == 1000), isTrue);
    expect(await target.months.isLocked('2026-05'), isTrue);
    final settlement = await target.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    );
    expect(settlement.workers.single.netCents, 3000 + 2000);
  });

  test('损坏的 JSON 无法覆盖原账', () async {
    await seed(source);
    expect(
      () => source.backup.inspect('{ 这不是 json'),
      throwsA(isA<BackupFailure>()),
    );

    final records = await source.records.listRange(
      DateRange.of('2026-01-01', '2026-12-31'),
    );
    expect(records.length, 2, reason: '校验失败不得触碰数据库');
  });

  test('非本应用备份 / 版本过高 被拒绝', () async {
    await seed(source);
    final json = await source.backup.buildJson();
    final map = jsonDecode(json) as Map<String, Object?>;

    final wrongFormat = jsonDecode(jsonEncode({...map, 'format': 'other_app'}));
    expect(
      () => source.backup.inspect(jsonEncode(wrongFormat)),
      throwsA(isA<BackupFailure>()),
    );

    final futureVersion = {...map, 'version': Defaults.backupVersion + 1};
    expect(
      () => source.backup.inspect(jsonEncode(futureVersion)),
      throwsA(isA<BackupFailure>()),
    );
  });

  test('恢复中途失败整体回滚', () async {
    await seed(source);
    final target = await Fixture.create();
    addTearDown(target.dispose);

    // 目标库先有一笔「原账」，用于验证失败后不丢
    final worker = await target.addWorker('原账工人');
    final toy = await target.addToy('原账玩具', priceTenThousandth: 100);
    await target.records.create(
      date: '2026-01-01',
      worker: worker,
      toy: toy,
      quantity: 7,
    );

    // 构造一条主键重复的非法备份
    final json = await source.backup.buildJson();
    final map = jsonDecode(json) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>;
    final records = List<Map<String, dynamic>>.from(
      (data[Tables.pieceRecords] as List).cast<Map<String, dynamic>>(),
    );
    records.add(Map<String, dynamic>.from(records.first)); // 重复主键
    data[Tables.pieceRecords] = records;
    final broken = jsonEncode(map);

    final preview = source.backup.inspect(broken);
    await expectLater(
      target.backup.restore(preview, persistSafetyBackup: (json) async => 'mem://x'),
      throwsA(anything),
    );

    final remaining = await target.records.listRange(
      DateRange.of('2026-01-01', '2026-12-31'),
    );
    expect(remaining.length, 1, reason: '事务回滚后原账应完好');
    expect(remaining.single.quantity, 7);
  });

  test('超 30 天的已删除记录默认不导出，可勾选包含', () async {
    var now = DateTime(2026, 6, 1);
    AppClock.override(() => now);
    addTearDown(AppClock.reset);

    final f = await Fixture.create();
    addTearDown(f.dispose);
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 1000);
    final keep = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    final expired = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 2,
    );
    await f.records.softDelete(expired.id);

    now = now.add(const Duration(days: 31));

    final defaultPreview = f.backup.inspect(await f.backup.buildJson());
    expect(defaultPreview.summary.recordCount, 1);
    expect(
      (defaultPreview.payload[Tables.pieceRecords] ?? const []).single['id'],
      keep.id,
    );

    final fullPreview = f.backup.inspect(
      await f.backup.buildJson(includeExpiredDeleted: true),
    );
    expect(fullPreview.summary.recordCount, 2);
  });

  test('备份文件名带版本与时间戳', () {
    final name = BackupService.buildFileName(now: DateTime(2026, 6, 7, 8, 9, 10));
    expect(name, contains('v${Defaults.backupVersion}'));
    expect(name, contains('20260607-080910'));
    expect(name.endsWith('.json'), isTrue);
  });
}
