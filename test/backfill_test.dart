import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/domain/rules/backfill_rules.dart';

import 'support/fixture.dart';

/// 业务日期 vs 录入时间：这条边界一旦糊掉，账就会记错日子。
///
/// 全部用例把时钟钉在 2026-11-22 16:32:41，再补录 11 号的活，
/// 断言"算在 11 号、录于今天"两边都不串。
void main() {
  final now = DateTime(2026, 11, 22, 16, 32, 41);
  final createdMillis = now.millisecondsSinceEpoch;
  late Fixture f;

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  group('BackfillRules 判定', () {
    test('今天补录前面的日期 → 是补录，并算出提前了几天', () {
      expect(
        BackfillRules.isBackfill(
          workDate: '2026-11-11',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        isTrue,
      );
      expect(
        BackfillRules.daysEarlier(
          workDate: '2026-11-11',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        11,
      );
      expect(
        BackfillRules.describe(
          workDate: '2026-11-11',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        '今天补录，账算在 11-11',
      );
    });

    test('今天记今天的活 → 不是补录', () {
      expect(
        BackfillRules.isBackfill(
          workDate: '2026-11-22',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        isFalse,
      );
    });

    test('昨天录的 11 号 → 不是"今天补录"', () {
      final yesterday = DateTime(2026, 11, 21, 9, 0, 0).millisecondsSinceEpoch;
      expect(
        BackfillRules.isBackfill(
          workDate: '2026-11-11',
          createdAtMillis: yesterday,
          today: '2026-11-22',
        ),
        isFalse,
      );
    });

    test('未来日期 / 非法日期一律不算补录', () {
      expect(
        BackfillRules.isBackfill(
          workDate: '2026-11-25',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        isFalse,
      );
      expect(
        BackfillRules.isBackfill(
          workDate: '2026-02-30',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        isFalse,
      );
      expect(
        BackfillRules.isBackfill(
          workDate: '',
          createdAtMillis: createdMillis,
          today: '2026-11-22',
        ),
        isFalse,
      );
    });
  });

  group('归集口径：按业务日期，不按录入时间', () {
    test('今天补录 11 号的计件，只出现在 11 号', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      final record = await f.records.create(
        date: '2026-11-11',
        worker: worker,
        toy: toy,
        quantity: 500,
      );

      // 两个时间各自正确
      expect(record.workDate, '2026-11-11');
      expect(record.date, '2026-11-11');
      expect(record.createdAtDate, '2026-11-22');
      expect(record.createdAtLabel, startsWith('2026-11-22 '));

      // 11 号能查到，22 号查不到——这是问题 7 的核心断言
      final onEleventh = await f.records.listByDate('2026-11-11');
      expect(onEleventh.single.id, record.id);
      expect(await f.records.listByDate('2026-11-22'), isEmpty);

      // 区间统计也只认 11 号
      final result = await f.settlements.settle(
        const DateRange(start: '2026-11-01', end: '2026-11-30'),
      );
      expect(result.totalPieceCents, 10000);
      expect(result.recordCount, 1);

      // 月度区间不含 22 号那天时，这笔也不该冒出来
      final twelfth = await f.settlements.settle(
        const DateRange(start: '2026-11-12', end: '2026-11-22'),
      );
      expect(twelfth.recordCount, 0);
      expect(twelfth.totalPieceCents, 0);
    });

    test('每天汇总 / 每日时间线落在 11 号，不落在今天', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);
      await f.records.create(
        date: '2026-11-11',
        worker: worker,
        toy: toy,
        quantity: 100,
      );

      final profile = await f.reports.profile(worker.id);
      expect(profile.days.single.date, '2026-11-11');
      expect(profile.firstDate, '2026-11-11');
      expect(profile.lastDate, '2026-11-11');

      // 今日概览不该把这笔算进"今天"
      final todayOverview = await f.settlements.overview('2026-11-22');
      expect(todayOverview.recordCount, 0);
      expect(todayOverview.pieceCents, 0);
    });

    test('补录的调整项同样归到业务日期', () async {
      final worker = await f.addWorker('张三');
      final adjustment = await f.adjustments.create(
        date: '2026-11-11',
        worker: worker,
        type: AdjustmentType.bonus,
        amountCents: 5000,
        remark: '补发全勤奖',
      );

      expect(adjustment.workDate, '2026-11-11');
      expect(adjustment.createdAtDate, '2026-11-22');

      final onEleventh = await f.adjustments.listRange(
        const DateRange(start: '2026-11-11', end: '2026-11-11'),
      );
      expect(onEleventh.single.id, adjustment.id);

      final onTwentySecond = await f.adjustments.listRange(
        const DateRange(start: '2026-11-22', end: '2026-11-22'),
      );
      expect(onTwentySecond, isEmpty);
    });
  });
}
