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

  test('金额恒存正数，方向由类型决定', () async {
    final worker = await f.addWorker('张三');

    final bonus = await f.adjustments.create(
      date: '2026-06-01',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤奖',
    );
    final deduction = await f.adjustments.create(
      date: '2026-06-01',
      worker: worker,
      type: AdjustmentType.deduction,
      amountCents: 500,
      remark: '迟到',
    );

    expect(bonus.amountCents, 2000);
    expect(bonus.signedCents, 2000);
    expect(deduction.signedCents, -500, reason: '扣款按负向计入应付');
  });

  test('金额必须大于 0', () async {
    final worker = await f.addWorker('李四');
    expect(
      () => f.adjustments.create(
        date: '2026-06-01',
        worker: worker,
        type: AdjustmentType.bonus,
        amountCents: 0,
        remark: '零头',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('备注必填', () async {
    final worker = await f.addWorker('王五');
    expect(
      () => f.adjustments.create(
        date: '2026-06-01',
        worker: worker,
        type: AdjustmentType.advance,
        amountCents: 1000,
        remark: '   ',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('修改、软删除、恢复', () async {
    final worker = await f.addWorker('赵六');
    final adjustment = await f.adjustments.create(
      date: '2026-06-02',
      worker: worker,
      type: AdjustmentType.hourly,
      amountCents: 3000,
      remark: '打杂 3 小时',
    );

    final updated = await f.adjustments.update(
      existing: adjustment,
      amountCents: 4000,
      remark: '打杂 4 小时',
    );
    expect(updated.amountCents, 4000);
    expect(updated.remark, '打杂 4 小时');

    await f.adjustments.softDelete(adjustment.id);
    expect(
      await f.adjustments.listRange(DateRange.of('2026-06-02', '2026-06-02')),
      isEmpty,
    );
    expect((await f.adjustments.listTrash()).length, 1);

    await f.adjustments.restore(adjustment.id);
    expect(
      (await f.adjustments.listRange(DateRange.of('2026-06-02', '2026-06-02'))).length,
      1,
    );
  });

  test('同 id 重复提交只落 1 笔', () async {
    final worker = await f.addWorker('孙七');
    await f.adjustments.create(
      date: '2026-06-03',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 100,
      remark: '奖励',
      adjustmentId: 'fixed-adj',
    );
    await f.adjustments.create(
      date: '2026-06-03',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 100,
      remark: '奖励',
      adjustmentId: 'fixed-adj',
    );
    final list = await f.adjustments.listRange(
      DateRange.of('2026-06-03', '2026-06-03'),
    );
    expect(list.length, 1);
  });
}
