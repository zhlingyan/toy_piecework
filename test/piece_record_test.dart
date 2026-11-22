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

  group('快照逻辑', () {
    test('落库即快照：档案改名、调价都不篡改历史', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);

      final record = await f.records.create(
        date: '2026-01-10',
        worker: worker,
        toy: toy,
        quantity: 100,
      );
      expect(record.workerNameSnapshot, '张三');
      expect(record.toyNameSnapshot, '小熊');
      expect(record.processSnapshot, '整件');
      expect(record.unitPriceSnapshot, 2000);
      expect(record.subtotalCents, 2000);

      await f.workers.update(worker.copyWith(name: '张三丰'));
      await f.toys.update(toy.copyWith(name: '大熊'));
      await f.toys.updatePrice(toy.id, 2500);

      final reloaded = await f.records.findById(record.id);
      expect(reloaded!.workerNameSnapshot, '张三');
      expect(reloaded.toyNameSnapshot, '小熊');
      expect(reloaded.unitPriceSnapshot, 2000);
      expect(reloaded.subtotalCents, 2000);
    });

    test('补录过去日期可手动填当时单价', () async {
      final worker = await f.addWorker('李四');
      final toy = await f.addToy('小兔', priceTenThousandth: 2500);

      final record = await f.records.create(
        date: '2025-12-01',
        worker: worker,
        toy: toy,
        quantity: 100,
        unitPriceTenThousandth: 2000,
      );
      expect(record.unitPriceSnapshot, 2000);
      expect(record.subtotalCents, 2000);
    });
  });

  group('修改规则', () {
    test('改数量沿用原单价并重算小计', () async {
      final worker = await f.addWorker('王五');
      final toy = await f.addToy('积木', priceTenThousandth: 350);
      final record = await f.records.create(
        date: '2026-02-03',
        worker: worker,
        toy: toy,
        quantity: 100,
      );
      expect(record.subtotalCents, 350);

      final updated = await f.records.update(
        existing: record,
        quantity: 200,
      );
      expect(updated.unitPriceSnapshot, 350, reason: '单价快照不能变');
      expect(updated.subtotalCents, 700);
    });

    test('只改备注不动小计（历史分位不漂移）', () async {
      final worker = await f.addWorker('赵六');
      final toy = await f.addToy('拼图', priceTenThousandth: 333);
      final record = await f.records.create(
        date: '2026-02-04',
        worker: worker,
        toy: toy,
        quantity: 3,
      );
      // 直接把小计改成「非重算值」，模拟旧账/人工修订数据
      await f.db.raw.update(
        Tables.pieceRecords,
        {'subtotal_cents': 999},
        where: 'id = ?',
        whereArgs: [record.id],
      );

      final updated = await f.records.update(
        existing: record,
        remark: '补录说明',
      );
      expect(updated.remark, '补录说明');
      expect(updated.subtotalCents, 999, reason: '只改备注必须保留原小计');
    });

    test('数量必须为正整数', () async {
      final worker = await f.addWorker('钱七');
      final toy = await f.addToy('陀螺', priceTenThousandth: 1000);
      expect(
        () => f.records.create(
          date: '2026-02-05',
          worker: worker,
          toy: toy,
          quantity: 0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('防重复提交（验收用例 2）', () {
    test('同一个 recordId 连写两次只落 1 笔', () async {
      final worker = await f.addWorker('孙八');
      final toy = await f.addToy('玩偶', priceTenThousandth: 500);
      const fixedId = 'fixed-record-id';

      await f.records.create(
        date: '2026-03-01',
        worker: worker,
        toy: toy,
        quantity: 10,
        recordId: fixedId,
      );
      final second = await f.records.create(
        date: '2026-03-01',
        worker: worker,
        toy: toy,
        quantity: 10,
        recordId: fixedId,
      );

      expect(second.id, fixedId);
      final all = await f.records.listByDate('2026-03-01');
      expect(all.length, 1);
    });
  });

  group('软删除与回收站', () {
    test('删除后不出现在正常列表，可在回收站看到并恢复', () async {
      final worker = await f.addWorker('周九');
      final toy = await f.addToy('风车', priceTenThousandth: 1200);
      final record = await f.records.create(
        date: '2026-04-01',
        worker: worker,
        toy: toy,
        quantity: 5,
      );

      await f.records.softDelete(record.id);
      expect(await f.records.listByDate('2026-04-01'), isEmpty);

      final trash = await f.records.listTrash();
      expect(trash.length, 1);
      expect(trash.first.isDeleted, isTrue);

      await f.records.restore(record.id);
      expect((await f.records.listByDate('2026-04-01')).length, 1);
    });

    test('已删除的记录不能直接修改', () async {
      final worker = await f.addWorker('吴十');
      final toy = await f.addToy('跳绳', priceTenThousandth: 800);
      final record = await f.records.create(
        date: '2026-04-02',
        worker: worker,
        toy: toy,
        quantity: 5,
      );
      await f.records.softDelete(record.id);
      final deleted = await f.records.findById(record.id);

      expect(
        () => f.records.update(existing: deleted!, quantity: 6),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('仓储基础能力', () {
    test('按区间与工人过滤，日期倒序', () async {
      final a = await f.addWorker('甲');
      final b = await f.addWorker('乙');
      final toy = await f.addToy('球', priceTenThousandth: 100);
      await f.records.create(date: '2026-05-01', worker: a, toy: toy, quantity: 1);
      await f.records.create(date: '2026-05-02', worker: a, toy: toy, quantity: 1);
      await f.records.create(date: '2026-05-02', worker: b, toy: toy, quantity: 1);

      final workerA = await f.records.listRange(
        DateRange.of('2026-05-01', '2026-05-02'),
        workerId: a.id,
      );
      expect(workerA.length, 2);
      expect(workerA.first.date, '2026-05-02');
    });
  });
}
