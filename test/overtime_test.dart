import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/money.dart';
import 'package:toy_piecework/data/models/toy.dart';
import 'package:toy_piecework/domain/rules/overtime_rules.dart';

import 'support/fixture.dart';

/// 加班相关的验收测试。
///
/// 这里的每条断言都直接对应「发了多少钱」，写死数字是刻意的：
/// 一旦有人改动算法，测试会立刻炸出来，而不是等月底工人来吵架。
void main() {
  group('倍率换算（整数，不碰 double）', () {
    test('0.20 元 × 1.5 = 0.30 元', () {
      expect(Money.applyMultiplier(2000, 1500), 3000);
    });

    test('0.035 元 × 1.5 = 0.0525 元（万分之一元不丢精度）', () {
      expect(Money.applyMultiplier(350, 1500), 525);
    });

    test('1.0 倍保持原价（不受四舍五入影响）', () {
      expect(Money.applyMultiplier(350, 1000), 350);
      expect(Money.applyMultiplier(1, 1000), 1);
    });

    test('1.25 倍这类非整数倍也能精确计算', () {
      // 2000 × 1.25 = 2500
      expect(Money.applyMultiplier(2000, 1250), 2500);
      // 350 × 1.25 = 437.5 => 四舍五入 438
      expect(Money.applyMultiplier(350, 1250), 438);
    });

    test('倍率展示', () {
      expect(Money.formatMultiplier(1500), '1.5');
      expect(Money.formatMultiplier(1000), '1.0');
      expect(Money.formatMultiplier(1250), '1.25');
      expect(Money.formatMultiplier(2000), '2.0');
    });
  });

  group('口径解析', () {
    Toy toy({int price = 2000, int overtimePrice = 0}) => Toy(
          id: 't1',
          name: '小熊',
          process: '整件',
          unitPriceTenThousandth: price,
          overtimePriceTenThousandth: overtimePrice,
          pinyinInitials: 'XX',
          isArchived: false,
          createdAt: 0,
          updatedAt: 0,
        );

    test('按倍数：0.20 × 1.5 => 0.30', () {
      final result = OvertimeRules.resolve(
        toy: toy(),
        basePriceTenThousandth: 2000,
        mode: OvertimeMode.multiplier,
        multiplierPerMille: 1500,
      );
      expect(result.priceTenThousandth, 3000);
      expect(result.multiplierPerMille, 1500);
      expect(result.multiplierLabel, '1.5');
    });

    test('按加班单价：用玩具档案里的加班价', () {
      final result = OvertimeRules.resolve(
        toy: toy(price: 2000, overtimePrice: 2600),
        basePriceTenThousandth: 2000,
        mode: OvertimeMode.unitPrice,
        multiplierPerMille: 1500,
      );
      expect(result.priceTenThousandth, 2600);
      expect(result.multiplierLabel, '1.3');
    });

    test('按加班单价但玩具没填：回退到倍数，不能算成零', () {
      final result = OvertimeRules.resolve(
        toy: toy(price: 2000, overtimePrice: 0),
        basePriceTenThousandth: 2000,
        mode: OvertimeMode.unitPrice,
        multiplierPerMille: 1500,
      );
      expect(result.priceTenThousandth, 3000, reason: '回退按 1.5 倍算，而非 0');
    });

    test('倍率被夹在 1.0 ~ 3.0 之间', () {
      final tooHigh = OvertimeRules.resolve(
        toy: toy(),
        basePriceTenThousandth: 2000,
        mode: OvertimeMode.multiplier,
        multiplierPerMille: 15000,
      );
      expect(tooHigh.priceTenThousandth, 6000, reason: '封顶 3 倍');

      final tooLow = OvertimeRules.resolve(
        toy: toy(),
        basePriceTenThousandth: 2000,
        mode: OvertimeMode.multiplier,
        multiplierPerMille: 500,
      );
      expect(tooLow.priceTenThousandth, 2000, reason: '兜底 1 倍');
    });

    test('下班时间判定', () {
      // 18:00 = 1080
      expect(
        OvertimeRules.shouldPrecheckOvertime(
            minuteOfDay: 18 * 60 + 30, workEndMinute: 1080, autoDetect: true),
        isTrue,
      );
      expect(
        OvertimeRules.shouldPrecheckOvertime(
            minuteOfDay: 17 * 60, workEndMinute: 1080, autoDetect: true),
        isFalse,
      );
      expect(
        OvertimeRules.shouldPrecheckOvertime(
            minuteOfDay: 22 * 60, workEndMinute: 1080, autoDetect: false),
        isFalse,
        reason: '关掉自动判定后一律不预勾',
      );
    });
  });

  group('落库与结算', () {
    late Fixture f;

    setUp(() async {
      f = await Fixture.create();
    });

    tearDown(() async {
      await f.dispose();
    });

    test('加班流水按加班单价入账，小计含加成', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      final record = await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 100,
        minuteOfDay: 19 * 60 + 20,
        overtime: true,
        overtimePriceTenThousandth: 3000,
        overtimeMultiplier: 1500,
      );

      expect(record.overtime, isTrue);
      expect(record.minuteOfDay, 1160);
      expect(record.timeLabel, '19:20');
      expect(record.unitPriceSnapshot, 2000, reason: '正常单价原样保留');
      expect(record.overtimePriceSnapshot, 3000);
      // 100 件 × 0.30 元 = 30.00 元
      expect(record.subtotalCents, 3000);
    });

    test('勾了加班却没有加班单价：直接报错，不静默按原价入账', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      expect(
        () => f.records.create(
          date: '2026-06-10',
          worker: worker,
          toy: toy,
          quantity: 100,
          overtime: true,
          overtimePriceTenThousandth: 0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('同价但一加班一正常：结算必须拆成两行', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      // 正常班 100 件 × 0.20 = 20.00
      await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 100,
        minuteOfDay: 9 * 60,
      );
      // 加班 100 件 × 0.30 = 30.00
      await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 100,
        minuteOfDay: 19 * 60,
        overtime: true,
        overtimePriceTenThousandth: 3000,
        overtimeMultiplier: 1500,
      );

      final result = await f.settlements.settle(
        const DateRange(start: '2026-06-10', end: '2026-06-10'),
      );
      final settlement = result.workers.single;

      expect(settlement.groups.length, 2, reason: '加班与正常班不能合并成一行');
      expect(settlement.pieceCents, 5000, reason: '20.00 + 30.00');

      final overtimeGroup =
          settlement.groups.firstWhere((group) => group.overtime);
      expect(overtimeGroup.quantity, 100);
      expect(overtimeGroup.subtotalCents, 3000);
      expect(overtimeGroup.overtimeSuffix, '加班 ×1.5');
      expect(overtimeGroup.pricingPriceTenThousandth, 3000);

      final normalGroup =
          settlement.groups.firstWhere((group) => !group.overtime);
      expect(normalGroup.subtotalCents, 2000);
      expect(normalGroup.overtimeSuffix, isEmpty);
    });

    test('加班不影响其他工人与调整项的计算', () async {
      final workerA = await f.addWorker('张三');
      final workerB = await f.addWorker('李四');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      await f.records.create(
        date: '2026-06-10',
        worker: workerA,
        toy: toy,
        quantity: 100,
        overtime: true,
        overtimePriceTenThousandth: 3000,
        overtimeMultiplier: 1500,
      );
      await f.records.create(
        date: '2026-06-10',
        worker: workerB,
        toy: toy,
        quantity: 50,
        overtime: true,
        overtimePriceTenThousandth: 4000,
        overtimeMultiplier: 2000,
      );

      final result = await f.settlements.settle(
        const DateRange(start: '2026-06-10', end: '2026-06-10'),
      );
      final byName = {
        for (final s in result.workers) s.workerName: s.pieceCents,
      };

      expect(byName['张三'], 3000); // 100 × 0.30
      expect(byName['李四'], 2000); // 50 × 0.40
    });

    test('按分钟排序：同日多笔按时间倒序', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 1,
        minuteOfDay: 8 * 60,
      );
      await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 1,
        minuteOfDay: 21 * 60,
      );
      await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 1,
        minuteOfDay: 14 * 60 + 5,
      );

      final list = await f.records.listByDate('2026-06-10');
      expect(list.map((r) => r.timeLabel).toList(), ['21:00', '14:05', '08:00']);
    });

    test('修改流水：把正常改成加班会重算小计，改回则恢复原价', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      final record = await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 100,
      );
      expect(record.subtotalCents, 2000);

      final asOvertime = await f.records.update(
        existing: record,
        overtime: true,
        overtimePriceTenThousandth: 3000,
        overtimeMultiplier: 1500,
      );
      expect(asOvertime.subtotalCents, 3000);
      expect(asOvertime.overtime, isTrue);

      final backToNormal = await f.records.update(
        existing: asOvertime,
        overtime: false,
      );
      expect(backToNormal.subtotalCents, 2000, reason: '改回正常班按原价重算');
      expect(backToNormal.overtimePriceSnapshot, 0);
    });

    test('只改备注时小计原样保留（不重新取整）', () async {
      final worker = await f.addWorker('张三');
      // 0.035 元 × 1 件 = 0.035 元 => 3.5 分 => 取整 4 分
      final toy = await f.addToy('小件', priceTenThousandth: 350);

      final record = await f.records.create(
        date: '2026-06-10',
        worker: worker,
        toy: toy,
        quantity: 1,
      );
      expect(record.subtotalCents, 4);

      final edited = await f.records.update(existing: record, remark: '返工');
      expect(edited.subtotalCents, 4);
      expect(edited.remark, '返工');
    });
  });
}
