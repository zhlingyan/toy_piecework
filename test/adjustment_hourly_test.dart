import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';
import 'package:toy_piecework/core/money.dart';
import 'package:toy_piecework/data/models/adjustment.dart';

import 'support/fixture.dart';

/// 计时工资按「工时 × 时薪」结算：金额必须由仓储统一推导，
/// 界面算一套、仓储存另一套是最容易发错钱的地方。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  group('计时工资换算', () {
    test('3.5 小时 × 25 元/时 = 87.50 元', () {
      expect(
        Money.hourlyCents(minutes: 210, rateCentsPerHour: 2500),
        8750,
      );
    });

    test('整除的情况不引入分位误差', () {
      expect(Money.hourlyCents(minutes: 60, rateCentsPerHour: 3333), 3333);
      expect(Money.hourlyCents(minutes: 30, rateCentsPerHour: 3333), 1667);
    });

    test('工时为 0 或时薪为 0 时结果为 0，不抛错', () {
      expect(Money.hourlyCents(minutes: 0, rateCentsPerHour: 2500), 0);
      expect(Money.hourlyCents(minutes: 60, rateCentsPerHour: 0), 0);
    });

    test('工时字符串解析：3.5 → 210 分钟，0.25 → 15 分钟', () {
      expect(Money.tryParseHoursToMinutes('3.5'), 210);
      expect(Money.tryParseHoursToMinutes('0.25'), 15);
      expect(Money.tryParseHoursToMinutes('２'), 120, reason: '兼容全角数字');
      expect(Money.tryParseHoursToMinutes(''), isNull);
      expect(Money.tryParseHoursToMinutes('abc'), isNull);
      expect(Money.tryParseHoursToMinutes('-2'), isNull);
    });

    test('工时展示去掉多余的 0', () {
      expect(Money.formatHours(210), '3.5');
      expect(Money.formatHours(120), '2');
      expect(Money.formatHours(15), '0.25');
    });
  });

  group('计时调整项落库', () {
    test('按工时算时，金额由工时 × 时薪推导，不采信传入的金额', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 1, // 故意传一个离谱的值
        workMinutes: 210,
        hourlyRateCents: 2500,
        remark: '打包',
      );

      expect(saved.amountCents, 8750);
      expect(saved.isByWorkTime, isTrue);
      expect(saved.workTimeLabel, '3.5 小时 × 25.00 元/时');
      expect(saved.signedCents, 8750, reason: '计时计入应付');
    });

    test('只填工时或只填时薪要报错，不能算成 0 元', () async {
      final worker = await f.addWorker('张三');
      expect(
        () => f.adjustments.create(
          date: '2026-06-10',
          worker: worker,
          type: AdjustmentType.hourly,
          amountCents: 100,
          workMinutes: 120,
          remark: '只填了工时',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => f.adjustments.create(
          date: '2026-06-10',
          worker: worker,
          type: AdjustmentType.hourly,
          amountCents: 100,
          hourlyRateCents: 2000,
          remark: '只填了时薪',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('超过 24 小时的工时被拒绝', () async {
      final worker = await f.addWorker('张三');
      expect(
        () => f.adjustments.create(
          date: '2026-06-10',
          worker: worker,
          type: AdjustmentType.hourly,
          amountCents: 0,
          workMinutes: Limits.maxWorkMinutes + 1,
          hourlyRateCents: 2000,
          remark: '明显多打了个 0',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('直接填金额时工时/时薪都是 0', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 5000,
        remark: '修机器半天',
      );
      expect(saved.amountCents, 5000);
      expect(saved.isByWorkTime, isFalse);
      expect(saved.workTimeLabel, '');
    });

    test('修改时从「直接填金额」切到「按工时算」，金额跟着重算', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 5000,
        remark: '先随手填的',
      );

      final updated = await f.adjustments.update(
        existing: saved,
        workMinutes: 90,
        hourlyRateCents: 2000,
        amountCents: 5000,
        remark: '改成按工时',
      );
      expect(updated.amountCents, 3000, reason: '1.5 小时 × 20 元 = 30 元');
      expect(updated.isByWorkTime, isTrue);
    });

    test('修改时把工时清成 0，退回按金额记账', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 0,
        workMinutes: 120,
        hourlyRateCents: 2500,
        remark: '打包',
      );
      expect(saved.amountCents, 5000);

      final updated = await f.adjustments.update(
        existing: saved,
        workMinutes: 0,
        hourlyRateCents: 0,
        amountCents: 4200,
      );
      expect(updated.amountCents, 4200);
      expect(updated.isByWorkTime, isFalse);
    });
  });

  group('时间与结算', () {
    test('调整项记录到分钟，并按分钟排序', () async {
      final worker = await f.addWorker('张三');
      await f.adjustments.create(
        date: '2026-06-10',
        minuteOfDay: 8 * 60,
        worker: worker,
        type: AdjustmentType.bonus,
        amountCents: 1000,
        remark: '早上记的',
      );
      await f.adjustments.create(
        date: '2026-06-10',
        minuteOfDay: 19 * 60 + 30,
        worker: worker,
        type: AdjustmentType.deduction,
        amountCents: 500,
        remark: '晚上记的',
      );

      final list = await f.adjustments.listRange(
        const DateRange(start: '2026-06-10', end: '2026-06-10'),
      );
      expect(list.length, 2);
      expect(list.first.timeLabel, '19:30', reason: '按时间倒序');
      expect(list.last.timeLabel, '08:00');
    });

    test('计时工资计入结算的「计时」项，且金额与逐笔取整一致', () async {
      final worker = await f.addWorker('张三');
      await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 0,
        workMinutes: 210,
        hourlyRateCents: 2500,
        remark: '打包',
      );
      await f.adjustments.create(
        date: '2026-06-11',
        worker: worker,
        type: AdjustmentType.bonus,
        amountCents: 2000,
        remark: '全勤',
      );

      final result = await f.settlements.settle(
        const DateRange(start: '2026-06-01', end: '2026-06-30'),
      );
      final row = result.workers.single;
      expect(row.hourlyCents, 8750);
      expect(row.bonusCents, 2000);
      expect(row.pieceCents, 0, reason: '只有调整项也要出现在结算里');
      expect(row.netCents, 10750);
      expect(result.hourlyTotal, 8750);
    });

    test('删除后的调整项不再进结算', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.advance,
        amountCents: 10000,
        remark: '预支生活费',
      );
      await f.adjustments.softDelete(saved.id);

      final result = await f.settlements.settle(
        const DateRange(start: '2026-06-01', end: '2026-06-30'),
      );
      expect(result.workers, isEmpty);
    });
  });

  group('模型兼容', () {
    test('老数据缺工时字段时按「直接填金额」处理', () {
      final adjustment = Adjustment.fromMap({
        'id': 'a1',
        'date': '2026-06-10',
        'worker_id': 'w1',
        'worker_name_snapshot': '张三',
        'type': 'hourly',
        'amount_cents': 5000,
        'remark': '修机器',
        'deleted_at': null,
        'created_at': 1,
        'updated_at': 1,
      });
      expect(adjustment.workMinutes, 0);
      expect(adjustment.hourlyRateCents, 0);
      expect(adjustment.isByWorkTime, isFalse);
      expect(adjustment.summaryLabel, '修机器');
    });

    test('计时按工时的摘要包含工时明细', () async {
      final worker = await f.addWorker('张三');
      final saved = await f.adjustments.create(
        date: '2026-06-10',
        worker: worker,
        type: AdjustmentType.hourly,
        amountCents: 0,
        workMinutes: 90,
        hourlyRateCents: 2000,
        remark: '打包',
      );
      expect(saved.summaryLabel, '1.5 小时 × 20.00 元/时 · 打包');
    });
  });
}
