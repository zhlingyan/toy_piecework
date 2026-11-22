import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/settlement_event.dart';

import 'support/fixture.dart';

/// 状态变更历史：只追加、时间戳不覆盖、理由选填、备份可恢复。
void main() {
  late Fixture f;
  final nov = DateRange.of('2026-11-01', '2026-11-30');

  setUp(() async {
    AppClock.override(() => DateTime(2026, 11, 22, 9, 30, 5));
    f = await Fixture.create();
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  Future<({String workerId, String recordId})> seed() async {
    final worker = await f.addWorker('张三', code: 'W001');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-11-05',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    return (workerId: worker.id, recordId: record.id);
  }

  test('每次结算 / 取消结算都追加一条，历史时间戳不被覆盖', () async {
    final ids = await seed();

    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: true,
    );
    var events = await f.settlementHistory.listForWorker(ids.workerId);
    expect(events.length, 1);
    expect(events.first.seq, 1);
    expect(events.first.action, SettlementAction.settled);
    expect(events.first.scope, SettlementEventScope.range);
    expect(events.first.months, ['2026-11']);
    expect(events.first.rangeStart, '2026-11-01');
    expect(events.first.rangeEnd, '2026-11-30');
    expect(events.first.happenedAt, '2026-11-22 09:30:05');
    expect(events.first.reason, '');
    expect(events.first.signature, '#1');

    // 推进时间后取消，并填一句理由
    AppClock.override(() => DateTime(2026, 11, 22, 10, 15, 30));
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: false,
      reason: '金额算错，重结',
    );
    events = await f.settlementHistory.listForWorker(ids.workerId);
    expect(events.length, 2);
    expect(events.first.action, SettlementAction.unsettled);
    expect(events.first.reason, '金额算错，重结');
    expect(events.first.happenedAt, '2026-11-22 10:15:30');
    expect(events.first.signature, '#2');
    // 关键：第一条记录的时间和理由都还是原来的，绝不能被覆盖
    expect(events.last.happenedAt, '2026-11-22 09:30:05');
    expect(events.last.reason, '');
    expect(events.last.action, SettlementAction.settled);
    expect(await f.settlementHistory.countForWorker(ids.workerId), 2);

    // 状态本身回到未结算，金额没被改动
    final worker = (await f.settlements.settle(nov)).workers.single;
    expect(worker.isFullySettled, isFalse);
    expect(worker.netCents, 2000);
  });

  test('取消理由留空（null 或空串）照常完成，理由记为空串', () async {
    final ids = await seed();
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: true,
    );
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: false,
      reason: null,
    );
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: true,
      reason: '',
    );
    final events = await f.settlementHistory.listForWorker(ids.workerId);
    expect(events.length, 3);
    expect(events[0].action, SettlementAction.settled);
    expect(events[1].action, SettlementAction.unsettled);
    expect(events[1].reason, '');
    expect(events[1].hasReason, isFalse);
    expect(events[2].reason, '');
  });

  test('逐笔结算 / 取消与「录入即结算」也追加历史（单笔范围）', () async {
    final worker = await f.addWorker('李四', code: 'W002');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-11-06',
      worker: worker,
      toy: toy,
      quantity: 50,
      settled: true, // 录入时直接勾「这一笔：已结算」
    );
    var events = await f.settlementHistory.listForWorker(worker.id);
    expect(events.length, 1);
    expect(events.first.scope, SettlementEventScope.entry);
    expect(events.first.action, SettlementAction.settled);
    expect(events.first.entryLabel, '2026-11-06 · 计件流水');

    await f.settlementEntries
        .setRecordSettled(record.id, settled: false);
    events = await f.settlementHistory.listForWorker(worker.id);
    expect(events.length, 2);
    expect(events.first.action, SettlementAction.unsettled);
    expect(events.first.scope, SettlementEventScope.entry);
    expect(events.last.happenedAt, '2026-11-22 09:30:05');
  });

  test('备份 v6 含变更历史，恢复后条数、顺序、理由与时间戳都不丢', () async {
    final ids = await seed();
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: true,
    );
    AppClock.override(() => DateTime(2026, 11, 22, 11, 0, 0));
    await f.settlementEntries.markRange(
      workerId: ids.workerId,
      months: const ['2026-11'],
      range: nov,
      settled: false,
      reason: '工人有异议',
    );

    final preview = f.backup.inspect(await f.backup.buildJson());
    expect(preview.summary.version, 6);
    expect(preview.summary.historyCount, 2);

    final target = await Fixture.create();
    addTearDown(target.dispose);
    await target.backup.restore(
      preview,
      persistSafetyBackup: (_) async => 'safety.json',
    );
    final restored = await target.settlementHistory.listForWorker(ids.workerId);
    expect(restored.length, 2);
    expect(restored.first.signature, '#2');
    expect(restored.first.reason, '工人有异议');
    expect(restored.first.happenedAt, '2026-11-22 11:00:00');
    expect(restored.last.happenedAt, '2026-11-22 09:30:05');
  });

  test('老备份（v5，没有历史表数据）安全降级为空，不报错', () async {
    final oldJson = jsonEncode({
      'format': Defaults.backupFormat,
      'version': 5,
      'exported_at': 0,
      'counts': <String, int>{},
      'data': <String, Object>{},
    });
    final preview = f.backup.inspect(oldJson);
    expect(preview.summary.version, 5);
    expect(preview.summary.historyCount, 0);

    final target = await Fixture.create();
    addTearDown(target.dispose);
    await target.backup.restore(
      preview,
      persistSafetyBackup: (_) async => 'safety.json',
    );
    expect(
      await target.settlementHistory.listForWorker('nobody'),
      isEmpty,
    );
  });
}
