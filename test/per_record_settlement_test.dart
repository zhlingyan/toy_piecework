import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/domain/rules/settlement_rules.dart';

import 'support/fixture.dart';

/// 逐笔结算：不再只能"整期一刀切"。
///
/// 两层标记并存，判定取并集：
/// * 整月标记 = "这一期发完了"的快捷方式；
/// * 单笔 `settled_at` = 更细的覆盖。
///
/// 关键不变量（任何组合下都必须成立）：
/// **已结算 + 未结算 == 应付**，且状态按笔数判定。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  Future<({Worker worker, String first, String second})> seedJune() async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20
    final first = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 500, // 100.00
    );
    final second = await f.records.create(
      date: '2026-06-20',
      worker: worker,
      toy: toy,
      quantity: 100, // 20.00
    );
    return (worker: worker, first: first.id, second: second.id);
  }

  test('只结其中一笔：状态为部分已结，金额精确拆开', () async {
    final seed = await seedJune();

    await f.settlementEntries.setRecordSettled(seed.first, settled: true);

    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    );
    final worker = result.workers.single;

    expect(worker.netCents, 12000);
    expect(worker.settledCents, 10000);
    expect(worker.unsettledCents, 2000);
    expect(worker.settledCount, 1);
    expect(worker.recordCount, 2);
    expect(worker.settlementStatus, SettlementStatus.partial);
    expect(
      worker.settledCents + worker.unsettledCents,
      worker.netCents,
      reason: '已结 + 未结必须等于应付',
    );
  });

  test('两笔都单独结清：已结算，未结为 0', () async {
    final seed = await seedJune();
    await f.settlementEntries.setRecordSettled(seed.first, settled: true);
    await f.settlementEntries.setRecordSettled(seed.second, settled: true);

    final result = await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    );
    final worker = result.workers.single;
    expect(worker.settlementStatus, SettlementStatus.settled);
    expect(worker.settledCents, 12000);
    expect(worker.unsettledCents, 0);
    expect(result.settledTotalCents, 12000);
    expect(result.unsettledTotalCents, 0);
    expect(result.settledRecordCount, 2);
    expect(result.totalRecordCount, 2);
  });

  test('整月已标后取消其中一笔：整月标记被展开，另一笔仍已结算', () async {
    final seed = await seedJune();
    await f.settlementMarks.markSettled(
      workerId: seed.worker.id,
      months: ['2026-06'],
      settled: true,
    );

    var worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settlementStatus, SettlementStatus.settled);

    await f.settlementEntries.setRecordSettled(seed.first, settled: false);

    // 整月标记必须被清掉，否则刷新后又会变回"已结算"
    expect(await f.settlementMarks.settledMonthsFor(seed.worker.id), isEmpty);

    worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settlementStatus, SettlementStatus.partial);
    expect(worker.settledCents, 2000, reason: '另一笔在展开时应保持已结算');
    expect(worker.unsettledCents, 10000);
    expect(worker.settledCount, 1);
  });

  test('录入时就能选择已结算', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('积木', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 50,
      settled: true,
    );

    expect(record.settledIndividually, isTrue);
    expect(record.settledAtLabel, isNotNull);

    final settlement = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(settlement.settlementStatus, SettlementStatus.settled);
    expect(settlement.settledCents, 500);
  });

  test('调整项也能单笔结算，扣款按负号进已结金额', () async {
    final seed = await seedJune();
    final deduction = await f.adjustments.create(
      date: '2026-06-15',
      worker: seed.worker,
      type: AdjustmentType.deduction,
      amountCents: 500,
      remark: '材料损耗',
    );

    await f.settlementEntries.setAdjustmentSettled(deduction.id, settled: true);

    final worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;

    expect(worker.netCents, 11500); // 120.00 - 5.00
    expect(worker.settledCents, -500);
    expect(worker.unsettledCents, 12000);
    expect(worker.settledCount, 1);
    expect(worker.recordCount, 3);
    expect(
      worker.settledCents + worker.unsettledCents,
      worker.netCents,
      reason: '负数的已结金额不能破坏恒等式',
    );
  });

  test('锁账只防改账，不拦结算标记', () async {
    final seed = await seedJune();
    await f.months.lock('2026-06');

    await f.settlementEntries.setRecordSettled(seed.first, settled: true);

    final worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settledCents, 10000);
  });

  test('取消整期：区间内的单笔标记一起清掉', () async {
    final seed = await seedJune();
    await f.settlementEntries.setRecordSettled(seed.first, settled: true);
    await f.settlementEntries.setRecordSettled(seed.second, settled: true);

    await f.settlementEntries.markRange(
      workerId: seed.worker.id,
      months: ['2026-06'],
      range: DateRange.of('2026-06-01', '2026-06-30'),
      settled: false,
    );

    final worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settlementStatus, SettlementStatus.unsettled);
    expect(worker.settledCents, 0);
    expect(await f.settlementMarks.settledMonthsFor(seed.worker.id), isEmpty);
  });

  test('已删除的流水不能标记结算', () async {
    final seed = await seedJune();
    await f.records.softDelete(seed.first);

    await expectLater(
      f.settlementEntries.setRecordSettled(seed.first, settled: true),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('逐笔状态与按月份口径在"跨月某月没活"时一致', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.settlementEntries.setRecordSettled(record.id, settled: true);

    // 区间覆盖 6~8 月，7、8 月没有账 —— 不能因此卡在"部分已结"
    final workerRow = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-08-31'),
    ))
        .workers
        .single;
    expect(workerRow.settlementStatus, SettlementStatus.settled);
    expect(workerRow.recordCount, 1);
    expect(workerRow.settledCount, 1);
  });

  test('整月标记与单笔标记并存时不重复计数', () async {
    final seed = await seedJune();
    await f.settlementMarks.markSettled(
      workerId: seed.worker.id,
      months: ['2026-06'],
      settled: true,
    );
    // 整月已标的情况下再单独标一笔，金额与笔数都只能算一次
    await f.settlementEntries.setRecordSettled(seed.first, settled: true);

    final worker = (await f.settlements.settle(
      DateRange.of('2026-06-01', '2026-06-30'),
    ))
        .workers
        .single;
    expect(worker.settledCents, 12000);
    expect(worker.settledCount, 2);
    expect(worker.recordCount, 2);
  });
}
