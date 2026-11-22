import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/money.dart';
import 'package:toy_piecework/domain/rules/price_rules.dart';

import 'support/fixture.dart';

/// 单价隔离：计数页改价只改这一笔，档案价永远只在「设置 → 玩具工序」里改。
///
/// 这是防串库的核心不变量，必须由测试钉死：
/// * 临时改价后玩具档案的单价一分不动；
/// * 之后改档案价，历史流水的单价快照也不受影响（各算各的）。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('临时改价只进流水，不回写玩具档案', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);

    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 10,
      // 0.25 元，与档案的 0.20 不同
      unitPriceTenThousandth: 2500,
    );

    expect(record.unitPriceSnapshot, 2500);
    expect(record.subtotalCents, 250); // 10 × 0.25 = 2.50

    final archived = await f.toys.findById(toy.id);
    expect(
      archived!.unitPriceTenThousandth,
      2000,
      reason: '档案单价必须原封不动，否则就是串库',
    );
  });

  test('之后改档案价，历史流水仍按原快照计算', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 100,
    );

    // 在档案管理里永久调价到 0.30
    await f.toys.update(
      (await f.toys.findById(toy.id))!.copyWith(unitPriceTenThousandth: 3000),
    );

    final reloaded = await f.records.findById(record.id);
    expect(reloaded!.unitPriceSnapshot, 2000, reason: '历史单价是快照，不跟着档案走');
    expect(reloaded.subtotalCents, 2000);

    // 新录入才用新价
    final next = await f.records.create(
      date: '2026-06-11',
      worker: worker,
      toy: (await f.toys.findById(toy.id))!,
      quantity: 100,
    );
    expect(next.unitPriceSnapshot, 3000);
  });

  test('不指定临时价时取档案价，不会被判定为临时调价', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 10,
    );

    expect(record.unitPriceSnapshot, 2000);
    expect(
      PriceRules.isTemporary(
        recordUnitPrice: record.unitPriceSnapshot,
        baseUnitPrice: toy.unitPriceTenThousandth,
      ),
      isFalse,
    );
  });

  test('档案价改过之后，老流水会被标成「临时调价」而不是被改价', () async {
    final worker = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    final record = await f.records.create(
      date: '2026-06-10',
      worker: worker,
      toy: toy,
      quantity: 10,
    );

    // 档案调到 0.30：这笔 0.20 的老账现在相对档案"不同"，
    // 标签的意义是提示"别拿它跟当前档案价对"，金额绝不变。
    final isTemp = PriceRules.isTemporary(
      recordUnitPrice: record.unitPriceSnapshot,
      baseUnitPrice: 3000,
    );
    expect(isTemp, isTrue);
    expect(record.subtotalCents, 200);
  });

  test('档案单价为 0（未设置）时不判定临时调价', () {
    expect(
      PriceRules.isTemporary(recordUnitPrice: 2500, baseUnitPrice: 0),
      isFalse,
      reason: '没有基准就没有偏离，宁可不标',
    );
    expect(
      PriceRules.isTemporary(recordUnitPrice: 2500, baseUnitPrice: 2500),
      isFalse,
    );
    expect(
      PriceRules.isTemporary(recordUnitPrice: 2500, baseUnitPrice: 2000),
      isTrue,
    );
  });

  test('单价展示文本不带「元」，可直接回填输入框', () async {
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);

    expect(toy.priceLabel, '0.20');
    expect(toy.priceLabel.contains('元'), isFalse, reason: '单位由展示层单独给');
    // 关键：回填到数字输入框后必须能解析回来（早先这里带着「元」，解析必失败）
    expect(Money.tryParsePrice(toy.priceLabel), 2000);
  });
}
