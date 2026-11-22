import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('年度报表：按工人 + 玩具 + 工序汇总，跨年数据不串年', () async {
    final zhang = await f.addWorker('张三');
    final li = await f.addWorker('李四');
    final bear = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20
    final bearFill = await f.addToy(
      '小熊',
      process: '填充',
      priceTenThousandth: 500,
    ); // 0.05

    // 2025 年：不计入 2026 报表
    await f.records.create(
      date: '2025-12-31',
      worker: zhang,
      toy: bear,
      quantity: 1000,
    );
    // 2026 年：张三 小熊整件 1000 件、填充 200 件；李四 小熊整件 500 件
    await f.records.create(
      date: '2026-01-05',
      worker: zhang,
      toy: bear,
      quantity: 1000,
    );
    await f.records.create(
      date: '2026-03-08',
      worker: zhang,
      toy: bearFill,
      quantity: 200,
    );
    await f.records.create(
      date: '2026-12-31',
      worker: li,
      toy: bear,
      quantity: 500,
    );

    final report = await f.reports.annual(2026);

    expect(report.year, 2026);
    expect(report.workerCount, 2);
    // 张三 1000 + 200 = 1200 件，李四 500 件
    expect(report.quantity, 1700);
    // 1000×0.20=200.00 + 200×0.05=10.00 + 500×0.20=100.00 = 310.00
    expect(report.cents, 31000);

    final zhangRow = report.workers.firstWhere((w) => w.workerId == zhang.id);
    expect(zhangRow.quantity, 1200);
    expect(zhangRow.cents, 21000);
    expect(zhangRow.lines.length, 2, reason: '不同工序必须分行');
    expect(zhangRow.workerCode, zhang.code);

    // 按产量倒序：张三 1200 件在前
    expect(report.workers.first.workerId, zhang.id);
    expect(report.topWorker?.workerId, zhang.id);
  });

  test('年度报表：已删除的流水不计入', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('小兔', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-04-01',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.records.softDelete(record.id);

    final report = await f.reports.annual(2026);
    expect(report.isEmpty, isTrue);
    expect(report.quantity, 0);
  });

  test('员工档案：累计数据、历史玩具与每日时间线（含只有调整项的日期）', () async {
    final worker = await f.addWorker('赵六');
    final toy = await f.addToy('小鸭', priceTenThousandth: 2500); // 0.25

    await f.records.create(
      date: '2026-05-01',
      worker: worker,
      toy: toy,
      quantity: 200,
    );
    await f.records.create(
      date: '2026-05-03',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    // 只有调整项、没有计件的一天
    await f.adjustments.create(
      date: '2026-05-04',
      worker: worker,
      type: AdjustmentType.advance,
      amountCents: 5000,
      remark: '预支',
    );

    final profile = await f.reports.profile(worker.id);

    expect(profile.totalQuantity, 300);
    expect(profile.totalCents, 7500); // 300 × 0.25 = 75.00
    expect(profile.firstDate, '2026-05-01');
    expect(profile.lastDate, '2026-05-03');
    expect(profile.toys.length, 1);
    expect(profile.toys.first.quantity, 300);

    expect(profile.days.length, 3);
    // 时间线倒序：05-04 在最前
    expect(profile.days.first.date, '2026-05-04');
    expect(profile.days.first.recordCount, 0);
    expect(profile.days.first.adjustmentCount, 1);
    expect(profile.days.first.adjustmentNetCents, -5000, reason: '预支为负');

    final mayThird = profile.days.firstWhere((day) => day.date == '2026-05-03');
    expect(mayThird.quantity, 100);
    expect(mayThird.pieceCents, 2500);
    expect(mayThird.adjustmentCount, 0);
  });

  test('员工档案：累计按快照计算，调价后历史金额不变', () async {
    final worker = await f.addWorker('孙七');
    final toy = await f.addToy('小车', priceTenThousandth: 2000);

    await f.records.create(
      date: '2026-02-01',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    // 调价后新流水按新价
    await f.toys.updatePrice(toy.id, 2500);
    final updated = await f.toys.findById(toy.id);
    await f.records.create(
      date: '2026-02-02',
      worker: worker,
      toy: updated!,
      quantity: 100,
    );

    final profile = await f.reports.profile(worker.id);
    expect(profile.totalQuantity, 200);
    // 20.00 + 25.00，不是 200 件 × 新价 25.00（档案看的是快照金额）
    expect(profile.totalCents, 4500);
    expect(profile.toys.length, 1, reason: '同一玩具同一工序合并成一行');
    expect(profile.toys.first.cents, 4500);
  });

  test('员工档案：没有记录时返回空档案但不抛错', () async {
    final worker = await f.addWorker('周八');
    final profile = await f.reports.profile(worker.id);
    expect(profile.isEmpty, isTrue);
    expect(profile.days, isEmpty);
    expect(profile.firstDate, isNull);
  });
}
