import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';

import 'support/fixture.dart';

/// v1.8 回归：结算状态单一数据源 + 笔数口径一致 + 出勤名单。
///
/// 对应两个真实 bug：
/// * 计数页把「工人 id 集合」当「月份集合」传给 isSettled，整月结算不同步；
/// * 「笔数」只数计件、「已结笔数」分母数计件 + 调整项，出现 16 与 20/20 并列。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('loadState：整月标记对计件与调整项同时生效，取消后立刻回退', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final june = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    final bonus = await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤',
    );
    final july = await f.records.create(
      date: '2026-07-05',
      worker: worker,
      toy: toy,
      quantity: 50,
    );

    var state = await f.settlementMarks.loadState();
    expect(state.isPieceSettled(june), isFalse);
    expect(state.isAdjustmentSettled(bonus), isFalse);
    expect(state.isPieceSettled(july), isFalse);

    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: true,
    );
    state = await f.settlementMarks.loadState();
    expect(state.isPieceSettled(june), isTrue, reason: '6 月整月已结');
    expect(state.isAdjustmentSettled(bonus), isTrue, reason: '补贴随整月已结');
    expect(state.isPieceSettled(july), isFalse, reason: '7 月不受影响');
    expect(state.isMarkSettled(worker.id, '2026-06'), isTrue);
    expect(state.isMarkSettled(worker.id, '2026-07'), isFalse);

    // 取消后快照立刻回到未结，不留旧缓存（跨页面同步的前提）
    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: false,
    );
    state = await f.settlementMarks.loadState();
    expect(state.isPieceSettled(june), isFalse);
    expect(state.isAdjustmentSettled(bonus), isFalse);
  });

  test('loadState：逐笔 settled_at 独立于整月标记', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('车', priceTenThousandth: 1000);
    final settledOne = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 10,
      settled: true,
    );
    final plainOne = await f.records.create(
      date: '2026-06-11',
      worker: worker,
      toy: toy,
      quantity: 10,
    );
    final state = await f.settlementMarks.loadState();
    expect(state.isPieceSettled(settledOne), isTrue);
    expect(state.isPieceSettled(plainOne), isFalse);
  });

  test('状态快照与结算聚合 SQL 口径一致（结算页 = 计数页）', () async {
    final a = await f.addWorker('甲');
    final b = await f.addWorker('乙');
    final toy = await f.addToy('球', priceTenThousandth: 1000);
    await f.records.create(
      date: '2026-06-10',
      worker: a,
      toy: toy,
      quantity: 10,
    );
    await f.records.create(
      date: '2026-06-11',
      worker: b,
      toy: toy,
      quantity: 10,
    );
    await f.adjustments.create(
      date: '2026-06-11',
      worker: a,
      type: AdjustmentType.deduction,
      amountCents: 500,
      remark: '损耗',
    );

    await f.settlementMarks.markSettled(
      workerId: a.id,
      months: ['2026-06'],
      settled: true,
    );

    final state = await f.settlementMarks.loadState();
    final range = DateRange.of('2026-06-01', '2026-06-30');
    final result = await f.settlements.settle(range);
    final records = await f.records.listRange(range);
    final adjustments = await f.adjustments.listRange(range);

    // 用计数页/明细页共用的快照数出来的已结笔数，必须等于结算页 SQL 数出来的
    final countedSettled = records.where(state.isPieceSettled).length +
        adjustments.where(state.isAdjustmentSettled).length;
    expect(countedSettled, 2, reason: '甲的 1 笔计件 + 1 笔扣款');
    expect(countedSettled, result.settledRecordCount);
    expect(result.workers.length, 2);
  });

  test('总笔数 = 计件 + 调整项，分子分母同口径', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('积木', priceTenThousandth: 1000);
    await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    await f.records.create(
      date: '2026-06-02',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    for (final type in AdjustmentType.values) {
      await f.adjustments.create(
        date: '2026-06-03',
        worker: worker,
        type: type,
        amountCents: 100,
        remark: '测试',
      );
    }

    final range = DateRange.of('2026-06-01', '2026-06-30');
    final result = await f.settlements.settle(range);
    // 2 笔计件 + 4 笔调整项；之前「笔数」只有 2，才会和「已结 6/6」打架
    expect(result.recordCount, 6);
    expect(result.totalRecordCount, 6);
    expect(result.recordCount, result.totalRecordCount,
        reason: '「总笔数」与「已结笔数」分母必须同源');
    expect(result.settledRecordCount, 0);
    expect(result.workers.single.recordCount, 6);

    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: true,
    );
    final settledResult = await f.settlements.settle(range);
    expect(settledResult.settledRecordCount, 6);
    expect(settledResult.totalRecordCount, 6);
    expect(
      settledResult.settledRecordCount,
      lessThanOrEqualTo(settledResult.totalRecordCount),
    );
  });

  test('出勤名单：出勤/总人数、已出勤高亮数据、未出勤置灰数据', () async {
    final a = await f.addWorker('甲');
    final b = await f.addWorker('乙');
    final c = await f.addWorker('丙');
    final toy = await f.addToy('球', priceTenThousandth: 1000);
    await f.records.create(
      date: '2026-06-20',
      worker: a,
      toy: toy,
      quantity: 3,
    ); // 30 分
    await f.adjustments.create(
      date: '2026-06-20',
      worker: b,
      type: AdjustmentType.bonus,
      amountCents: 500,
      remark: '奖励',
    );

    final overview = await f.settlements.overview('2026-06-20');
    expect(overview.attendanceLabel, '2/3');
    expect(overview.workerCount, 2);
    expect(overview.totalWorkerCount, 3);
    expect(overview.people.length, 3);
    expect(overview.presentCount, 2);
    expect(overview.absentCount, 1);
    // 已出勤排前、未出勤置后
    expect(overview.people[0].present, isTrue);
    expect(overview.people[1].present, isTrue);
    expect(overview.people[2].present, isFalse);

    final byId = {for (final p in overview.people) p.workerId: p};
    expect(byId[a.id]!.recordCount, 1);
    expect(byId[a.id]!.netCents, 30);
    expect(byId[b.id]!.recordCount, 1);
    expect(byId[b.id]!.netCents, 500);
    expect(byId[c.id]!.recordCount, 0);
    expect(byId[c.id]!.netCents, 0);
    expect(overview.workerCount, lessThanOrEqualTo(overview.totalWorkerCount));
  });

  test('总人数为 0 时出勤安全展示 0/0 且名单为空', () async {
    final overview = await f.settlements.overview('2026-06-20');
    expect(overview.attendanceLabel, '0/0');
    expect(overview.people, isEmpty);
    expect(overview.presentCount, 0);
    expect(overview.absentCount, 0);
  });

  test('已停用工人当日有账也计入总人数，出勤不超过总人数', () async {
    final active = await f.addWorker('在职');
    final archived = await f.addWorker('停用', code: 'X1');
    final toy = await f.addToy('球', priceTenThousandth: 1000);
    await f.workers.setArchived(archived.id, true);
    await f.records.create(
      date: '2026-06-20',
      worker: archived,
      toy: toy,
      quantity: 1,
    );

    final overview = await f.settlements.overview('2026-06-20');
    expect(overview.totalWorkerCount, 2, reason: '在职 1 + 当日有账的停用 1');
    expect(overview.workerCount, 1);
    expect(overview.attendanceLabel, '1/2');
    expect(overview.people.any((p) => p.isArchived && p.present), isTrue);
    expect(overview.people.any((p) => p.workerId == active.id && !p.present),
        isTrue);
  });
}
