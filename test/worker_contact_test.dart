import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/validators.dart';

import 'support/fixture.dart';

/// 工人联系方式：选填、可留空、老档案兼容、备份不丢。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  // 11010519491231002X 是一个校验位正确的示例号码
  const validIdCard = '11010519491231002X';

  test('电话与身份证号可以留空，老数据行为不变', () async {
    final worker = await f.addWorker('张三');

    expect(worker.phone, isEmpty);
    expect(worker.idCard, isEmpty);
    expect(worker.hasContact, isFalse);

    final reloaded = await f.workers.findById(worker.id);
    expect(reloaded!.phone, isEmpty);
    expect(reloaded.idCard, isEmpty);
    expect(reloaded.displayName, contains('W001'));
  });

  test('创建与修改都能保存联系方式，前后空格会被去掉', () async {
    final worker = await f.addWorker(
      '李四',
      phone: ' 13800001111 ',
      idCard: ' $validIdCard ',
    );
    expect(worker.phone, '13800001111');
    expect(worker.idCard, validIdCard);
    expect(worker.hasContact, isTrue);

    final updated = await f.workers.update(
      worker.copyWith(phone: '0571-88886666', idCard: ''),
    );
    expect(updated.phone, '0571-88886666');
    expect(updated.idCard, isEmpty);

    final reloaded = await f.workers.findById(worker.id);
    expect(reloaded!.phone, '0571-88886666');
    expect(reloaded.idCard, isEmpty, reason: '清空也要能存下去');
  });

  test('身份证号默认遮罩，位数异常时原样返回', () async {
    final worker = await f.addWorker('王五', idCard: validIdCard);
    expect(worker.maskedIdCard, '110105********002X');
    expect(worker.idCard, validIdCard);

    final short = worker.copyWith(idCard: '1234');
    expect(short.maskedIdCard, '1234');
  });

  test('温和校验：只给提醒，不抛异常', () {
    // 正常号码
    expect(Validators.phoneWarning('13800001111'), isNull);
    expect(Validators.phoneWarning('0571-8888 6666'), isNull);
    expect(Validators.phoneWarning('+86 138 0000 1111'), isNull);
    expect(Validators.phoneWarning(''), isNull);

    // 可疑但不阻断
    expect(Validators.phoneWarning('123'), isNotNull);
    expect(Validators.phoneWarning('138-abc'), isNotNull);

    expect(Validators.idCardWarning(validIdCard), isNull);
    expect(Validators.idCardWarning(''), isNull);
    expect(Validators.idCardWarning('110105194912310021'), isNotNull,
        reason: '校验位错误应提醒');
    expect(Validators.idCardWarning('11010519491231'), isNotNull);
    expect(Validators.idCardWarning('11010519491231002A'), isNotNull);
  });

  test('备份 v6：联系方式、结算标记与变更历史都能原样恢复', () async {
    final worker = await f.addWorker(
      '张三',
      phone: '13800001111',
      idCard: validIdCard,
    );
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    await f.settlementMarks.markSettled(
      workerId: worker.id,
      months: ['2026-06'],
      settled: true,
    );

    final json = await f.backup.buildJson();
    final preview = f.backup.inspect(json);
    expect(preview.summary.version, 6);
    expect(preview.summary.workerCount, 1);
    expect(preview.summary.settlementCount, 1);

    final target = await Fixture.create();
    addTearDown(target.dispose);
    await target.backup.restore(
      preview,
      persistSafetyBackup: (json) async => 'safety.json',
    );

    final restored = (await target.workers.listAll()).single;
    expect(restored.name, '张三');
    expect(restored.phone, '13800001111');
    expect(restored.idCard, validIdCard);
    expect(
      await target.settlementMarks.isSettled(restored.id, '2026-06'),
      isTrue,
    );

    final settlement = (await target.settlements.settle(
      const DateRange(start: '2026-06-01', end: '2026-06-30'),
    ))
        .workers
        .single;
    expect(settlement.settlementStatus.label, '已结算');
    expect(settlement.netCents, 2000);
  });

  test('恢复 v3 老备份（没有联系方式与结算表）不会报错', () async {
    final worker = await f.addWorker('李四');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );

    // 手工把 v6 备份降级成 v3：删掉新字段与结算表数据
    final json = await f.backup.buildJson();
    var text = json
        .replaceAll('"version": 6', '"version": 3')
        .replaceAll(RegExp(r'\s*"phone": "[^"]*",\n'), '\n')
        .replaceAll(RegExp(r'\s*"id_card": "[^"]*",\n'), '\n');
    expect(text.contains('"phone"'), isFalse);

    final preview = f.backup.inspect(text);
    expect(preview.summary.version, 3);
    expect(preview.summary.settlementCount, 0);

    final target = await Fixture.create();
    addTearDown(target.dispose);
    await target.backup.restore(
      preview,
      persistSafetyBackup: (json) async => 'safety.json',
    );
    final restored = (await target.workers.listAll()).single;
    expect(restored.phone, isEmpty);
    expect(restored.idCard, isEmpty);
  });
}
