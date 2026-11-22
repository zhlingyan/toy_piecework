import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';
import 'package:toy_piecework/domain/rules/trash_rules.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 6, 1, 10, 0, 0);
    AppClock.override(() => now);
    f = await Fixture.create();
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  test('删除 30 天内可恢复', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );

    await f.records.softDelete(record.id);
    now = now.add(const Duration(days: 29));

    expect((await f.records.listTrash()).length, 1);
    await f.records.restore(record.id);
    expect((await f.records.listByDate('2026-06-01')).length, 1);
  });

  test('超过 30 天：UI 隐藏且禁止恢复，但数据库仍保留记录', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('积木', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );

    await f.records.softDelete(record.id);
    now = now.add(const Duration(days: 31));

    // 回收站默认隐藏
    expect(await f.records.listTrash(), isEmpty);
    // 但数据还在（不物理删除）
    final withDeleted = await f.records.listRange(
      DateRange.of('2026-06-01', '2026-06-01'),
      includeDeleted: true,
    );
    expect(withDeleted.length, 1);
    expect(withDeleted.single.isDeleted, isTrue);

    // 恢复被拒绝
    expect(
      () => f.records.restore(record.id),
      throwsA(isA<TrashExpiredFailure>()),
    );

    // 运维视角可查超期项
    expect((await f.records.listTrash(includeExpired: true)).length, 1);
  });

  test('30 天整的边界仍然可恢复', () async {
    final worker = await f.addWorker('王五');
    final toy = await f.addToy('陀螺', priceTenThousandth: 1000);
    final record = await f.records.create(
      date: '2026-06-01',
      worker: worker,
      toy: toy,
      quantity: 1,
    );
    final deletedAt = AppClock.nowMillis();
    await f.records.softDelete(record.id);

    expect(
      TrashPolicy.canRestore(
        deletedAt,
        now: DateTime.fromMillisecondsSinceEpoch(deletedAt)
            .add(const Duration(days: 30)),
      ),
      isTrue,
    );
    expect(
      TrashPolicy.canRestore(
        deletedAt,
        now: DateTime.fromMillisecondsSinceEpoch(deletedAt)
            .add(const Duration(days: 30, hours: 1)),
      ),
      isFalse,
    );
  });

  test('调整项的回收站同样适用 30 天规则', () async {
    final worker = await f.addWorker('赵六');
    final adjustment = await f.adjustments.create(
      date: '2026-06-01',
      worker: worker,
      type: AdjustmentType.bonus,
      amountCents: 500,
      remark: '奖励',
    );
    await f.adjustments.softDelete(adjustment.id);
    now = now.add(const Duration(days: 31));

    expect(await f.adjustments.listTrash(), isEmpty);
    expect(
      () => f.adjustments.restore(adjustment.id),
      throwsA(isA<TrashExpiredFailure>()),
    );
  });
}
