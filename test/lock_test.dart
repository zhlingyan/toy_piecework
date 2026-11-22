import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('锁账后新增被拦截（验收用例 4）', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.months.lock('2026-06');

    expect(
      () => f.records.create(
        date: '2026-06-05',
        worker: worker,
        toy: toy,
        quantity: 1,
      ),
      throwsA(
        isA<LockedMonthFailure>().having(
          (e) => e.message,
          'message',
          contains('2026年6月'),
        ),
      ),
    );
  });

  test('锁账后修改、删除、回收站恢复全部被拦截', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('积木', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-06-06',
      worker: worker,
      toy: toy,
      quantity: 10,
    );
    final adjustment = await f.adjustments.create(
      date: '2026-06-06',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 100,
      remark: '奖励',
    );

    // 先删除一笔，再锁账，验证恢复也被拦截
    final deleted = await f.records.create(
      date: '2026-06-06',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    await f.records.softDelete(deleted.id);
    await f.months.lock('2026-06');

    expect(
      () => f.records.update(existing: record, quantity: 11),
      throwsA(isA<LockedMonthFailure>()),
    );
    expect(
      () => f.records.softDelete(record.id),
      throwsA(isA<LockedMonthFailure>()),
    );
    expect(
      () => f.records.restore(deleted.id),
      throwsA(isA<LockedMonthFailure>()),
    );
    expect(
      () => f.adjustments.update(existing: adjustment, amountCents: 200),
      throwsA(isA<LockedMonthFailure>()),
    );
    expect(
      () => f.adjustments.softDelete(adjustment.id),
      throwsA(isA<LockedMonthFailure>()),
    );
    expect(
      () => f.adjustments.create(
        date: '2026-06-07',
        worker: worker,
        type: AdjustmentType.advance,
        amountCents: 500,
        remark: '预支',
      ),
      throwsA(isA<LockedMonthFailure>()),
    );
  });

  test('跨月改期必须同时校验原月份与目标月份', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('陀螺', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-01-20',
      worker: worker,
      toy: toy,
      quantity: 1,
    );

    // 目标月份锁了
    await f.months.lock('2026-02');
    expect(
      () => f.records.update(existing: record, date: '2026-02-01'),
      throwsA(isA<LockedMonthFailure>().having(
        (e) => e.message,
        'message',
        contains('2026年2月'),
      )),
    );
    await f.months.unlock('2026-02');

    // 原月份锁了，目标月份没锁
    await f.months.lock('2026-01');
    expect(
      () => f.records.update(existing: record, date: '2026-02-01'),
      throwsA(isA<LockedMonthFailure>().having(
        (e) => e.message,
        'message',
        contains('2026年1月'),
      )),
    );
  });

  test('解锁后恢复可写', () async {
    final worker = await f.addWorker('赵六');
    final toy = await f.addToy('球', priceTenThousandth: 1000);
    await f.months.lock('2026-07');
    expect(
      () => f.records.create(
        date: '2026-07-01',
        worker: worker,
        toy: toy,
        quantity: 1,
      ),
      throwsA(isA<LockedMonthFailure>()),
    );

    await f.months.unlock('2026-07');
    final record = await f.records.create(
      date: '2026-07-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    expect(record.quantity, 1);
  });

  test('锁账不影响查询与结算', () async {
    final worker = await f.addWorker('孙七');
    final toy = await f.addToy('玩偶', priceTenThousandth: 2000);
    await f.records.create(date: '2026-08-01', worker: worker, toy: toy, quantity: 10);
    await f.months.lock('2026-08');

    final result = await f.settlements.settle(DateRange.of('2026-08-01', '2026-08-31'));
    expect(result.workers.single.pieceCents, 200, reason: '10 件 × 0.20 元 = 2.00 元');
    expect(await f.months.isLocked('2026-08'), isTrue);
    expect(await f.months.lockedMonths(), {'2026-08'});
  });
}
