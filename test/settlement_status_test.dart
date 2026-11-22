import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/domain/rules/settlement_rules.dart';

import 'support/fixture.dart';

/// 结算状态：按「人 + 月」标记，金额按月归属拆分。
///
/// 关键不变量：**已结算 + 未结算 == 应付**，任何标记组合下都必须成立。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  Future<void> seedTwoMonths() async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20 元

    // 6 月：计件 100.00 + 补贴 20.00 = 120.00
    await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 500,
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤',
    );

    // 7 月：计件 20.00 - 扣款 5.00 = 15.00
    await f.records.create(
      date: '2026-07-05',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.adjustments.create(
      date: '2026-07-05',
      worker: worker,
      type: AdjustmentType.deduction,
      amountCents: 500,
      remark: '材料损耗',
    );
  }

  test('默认全部未结算，金额按月拆开且合计对得上', () async {
    await seedTwoMonths();

    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-07-31'),
    );
    final worker = result.workers.single;

    expect(worker.netCents, 13500); // 120.00 + 15.00
    expect(worker.monthNetCents, {'2026-06': 12000, '2026-07': 1500});
    expect(worker.activeMonths, ['2026-06', '2026-07']);
    expect(worker.settledMonths, isEmpty);
    expect(worker.settlementStatus, SettlementStatus.unsettled);
    expect(worker.settledCents, 0);
    expect(worker.unsettledCents, 13500);

    expect(result.settledTotalCents, 0);
    expect(result.unsettledTotalCents, 13500);
    expect(result.settledWorkerCount, 0);
    expect(result.unsettledWorkerCount, 1);
  });

  test('标记 6 月：部分已结，金额拆分精确', () async {
    await seedTwoMonths();
    final worker = await f.workers.findByCode('W001');

    await f.settlementMarks.markSettled(
      workerId: worker!.id,
      months: ['2026-06'],
      settled: true,
    );

    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-07-31'),
    );
    final settlement = result.workers.single;
    expect(settlement.settlementStatus, SettlementStatus.partial);
    expect(settlement.settledCents, 12000);
    expect(settlement.unsettledCents, 1500);
    expect(
      settlement.settledCents + settlement.unsettledCents,
      settlement.netCents,
      reason: '已结 + 未结必须等于应付',
    );
    // 部分已结的工人整笔算未结，避免误以为已经结清
    expect(result.settledTotalCents, 0);
    expect(result.unsettledTotalCents, 13500);
  });

  test('两个月都标记：已结清；只看单月区间也显示已结算', () async {
    await seedTwoMonths();
    final worker = await f.workers.findByCode('W001');

    await f.settlementMarks.markSettled(
      workerId: worker!.id,
      months: ['2026-06', '2026-07'],
      settled: true,
    );

    final both = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-07-31'),
    );
    final settlement = both.workers.single;
    expect(settlement.settlementStatus, SettlementStatus.settled);
    expect(settlement.settledCents, 13500);
    expect(settlement.unsettledCents, 0);
    expect(both.settledTotalCents, 13500);
    expect(both.unsettledTotalCents, 0);
    expect(both.settledWorkerCount, 1);

    final june = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    );
    expect(june.workers.single.settlementStatus, SettlementStatus.settled);
    expect(june.workers.single.netCents, 12000);
  });

  test('取消标记后回到未结算，金额不受影响', () async {
    await seedTwoMonths();
    final worker = await f.workers.findByCode('W001');

    await f.settlementMarks.markSettled(
      workerId: worker!.id,
      months: ['2026-06'],
      settled: true,
    );
    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: false,
    );

    expect(
      await f.settlementMarks.settledMonthsFor(worker.id),
      isEmpty,
    );
    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-07-31'),
    );
    expect(result.workers.single.settlementStatus, SettlementStatus.unsettled);
    expect(result.workers.single.netCents, 13500);
  });

  test('一个工人标记不影响同区间的其他人', () async {
    await seedTwoMonths();
    final zhang = await f.workers.findByCode('W001');
    final li = await f.addWorker('李四');
    final toy = await f.addToy('积木', priceTenThousandth: 1000);
    await f.records.create(
      date: '2026-06-12',
      worker: li,
      toy: toy,
      quantity: 50,
    );

    await f.settlementMarks.markSettled(
      workerId: zhang!.id,
      months: ['2026-06', '2026-07'],
      settled: true,
    );

    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-07-31'),
    );
    expect(result.workers.length, 2);
    final liRow = result.workers.firstWhere((w) => w.workerName == '李四');
    expect(liRow.settlementStatus, SettlementStatus.unsettled);
    expect(liRow.netCents, 500);

    // 筛选：已结算只剩张三
    final settledOnly = result.filterBy(SettlementStatus.settled);
    expect(settledOnly.map((w) => w.workerName), ['张三']);
    expect(
      result.filterBy(SettlementStatus.unsettled).map((w) => w.workerName),
      ['李四'],
    );
    // 部分已结的工人不会出现在「已结算」里
    expect(result.filterBy(null).length, 2);
  });

  test('跨月但某月没干活：只按有账月份判定，不会卡在部分已结', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: true,
    );

    // 区间覆盖 6~8 月，但 7、8 月没有账
    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-08-31'),
    );
    expect(result.workers.single.settlementStatus, SettlementStatus.settled);
  });

  test('批量标记与按月查询', () async {
    await seedTwoMonths();
    final a = await f.workers.findByCode('W001');
    final b = await f.addWorker('李四');

    await f.settlementMarks.markMany(
      workerIds: [a!.id, b.id],
      months: ['2026-06'],
      settled: true,
    );

    final settledA = await f.settlementMarks.settledMonthsFor(a.id);
    expect(settledA, {'2026-06'});
    expect(
      await f.settlementMarks.settledMonthsOf(a.id, ['2026-06', '2026-07']),
      {'2026-06'},
    );
    expect(await f.settlementMarks.isSettled(b.id, '2026-06'), isTrue);
    expect(await f.settlementMarks.isSettled(b.id, '2026-07'), isFalse);

    final marks = await f.settlementMarks.byWorkerMonth(
      workerIds: [a.id, b.id],
      months: ['2026-06'],
    );
    expect(marks.length, 2);
  });
}
