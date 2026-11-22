import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/money.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('验收用例 3：计件 100 + 补贴 20 + 计时 10 - 扣款 5 - 预支 15 = 110.00', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20 元

    await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 500, // 500 × 0.20 = 100.00
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤',
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.hourly,
      amountCents: 1000,
      remark: '打包 2 小时',
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.deduction,
      amountCents: 500,
      remark: '材料损耗',
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: worker,
      type: AdjustmentType.advance,
      amountCents: 1500,
      remark: '预支生活费',
    );

    final result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    expect(result.workers.length, 1);
    final settlement = result.workers.first;
    expect(settlement.pieceCents, 10000);
    expect(settlement.bonusCents, 2000);
    expect(settlement.hourlyCents, 1000);
    expect(settlement.deductionCents, 500);
    expect(settlement.advanceCents, 1500);
    expect(settlement.netCents, 11000);
    expect(Money.formatCents(settlement.netCents), '110.00');
  });

  test('同工序中途调价必须拆成两行，合计 45.00', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('积木', priceTenThousandth: 2000);

    await f.records.create(
      date: '2026-06-11',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.records.create(
      date: '2026-06-11',
      worker: worker,
      toy: toy,
      quantity: 100,
      unitPriceTenThousandth: 2500,
    );

    final result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    final groups = result.workers.single.groups;
    expect(groups.length, 2, reason: '不同单价快照必须分行');
    expect(groups.map((g) => g.unitPriceTenThousandth).toSet(), {2000, 2500});
    expect(groups.every((g) => g.quantity == 100), isTrue);
    expect(result.workers.single.pieceCents, 4500);
    expect(Money.formatCents(result.workers.single.pieceCents), '45.00');
  });

  test('只有调整项的工人也进入结算清单', () async {
    final worker = await f.addWorker('王五');
    await f.adjustments.create(
      date: '2026-06-12',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '安全奖',
    );

    final result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    expect(result.workers.length, 1);
    final settlement = result.workers.single;
    expect(settlement.onlyAdjustments, isTrue);
    expect(settlement.pieceCents, 0);
    expect(settlement.netCents, 2000);
  });

  test('应付为负时保留原值并标记（不截断为 0）', () async {
    final worker = await f.addWorker('赵六');
    await f.adjustments.create(
      date: '2026-06-13',
      worker: worker,
      type: AdjustmentType.deduction,
      amountCents: 5000,
      remark: '赔偿',
    );

    final result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    final settlement = result.workers.single;
    expect(settlement.netCents, -5000);
    expect(settlement.isNegative, isTrue);
    expect(Money.formatCents(settlement.netCents), '-50.00');
  });

  test('区间边界含首尾，区间外与已删除不计入', () async {
    final worker = await f.addWorker('孙七');
    final toy = await f.addToy('陀螺', priceTenThousandth: 1000);

    await f.records.create(date: '2026-05-31', worker: worker, toy: toy, quantity: 1);
    final inside = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    await f.records.create(date: '2026-06-30', worker: worker, toy: toy, quantity: 1);
    await f.records.create(date: '2026-07-01', worker: worker, toy: toy, quantity: 1);

    var result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    expect(result.recordCount, 2);
    // 1 件 × 0.10 元 = 10 分，两笔共 20 分
    expect(result.workers.single.pieceCents, 20);

    await f.records.softDelete(inside.id);
    result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    expect(result.recordCount, 1);
    expect(result.workers.single.pieceCents, 10);
  });

  test('归档工人的历史仍可结算', () async {
    final worker = await f.addWorker('周八');
    final toy = await f.addToy('风车', priceTenThousandth: 500);
    await f.records.create(date: '2026-06-15', worker: worker, toy: toy, quantity: 10);
    await f.workers.setArchived(worker.id, true);

    final result = await f.settlements.settle(DateRange.of('2026-06-01', '2026-06-30'));
    expect(result.workers.single.workerName, '周八');
    expect(result.workers.single.isArchived, isTrue);
    expect(result.workers.single.pieceCents, 50);
  });

  test('概览：当日笔数、出勤人数、计件总额', () async {
    final a = await f.addWorker('甲');
    final b = await f.addWorker('乙');
    final c = await f.addWorker('丙');
    final toy = await f.addToy('球', priceTenThousandth: 1000);

    await f.records.create(date: '2026-06-20', worker: a, toy: toy, quantity: 3);
    await f.records.create(date: '2026-06-20', worker: b, toy: toy, quantity: 2);
    await f.adjustments.create(
      date: '2026-06-20',
      worker: c,
      type: AdjustmentType.bonus,
      amountCents: 500,
      remark: '奖励',
    );

    final overview = await f.settlements.overview('2026-06-20');
    expect(overview.recordCount, 2);
    expect(overview.workerCount, 3, reason: '仅有调整项也算出勤');
    expect(overview.pieceCents, 50, reason: '3 件 + 2 件，每件 0.10 元 = 10 分');
    expect(overview.adjustmentCount, 1);
  });

  test('多工人结果按应付倒序', () async {
    final a = await f.addWorker('甲');
    final b = await f.addWorker('乙');
    final toy = await f.addToy('车', priceTenThousandth: 1000);
    await f.records.create(date: '2026-06-21', worker: a, toy: toy, quantity: 10);
    await f.records.create(date: '2026-06-21', worker: b, toy: toy, quantity: 99);

    final result = await f.settlements.settle(DateRange.of('2026-06-21', '2026-06-21'));
    expect(result.workers.first.workerName, '乙');
    expect(result.totalNetCents, 1090);
  });
}
