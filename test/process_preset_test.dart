import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/failures.dart';

import 'support/fixture.dart';

/// 工序选项：预置项开箱即用，自定义项落库沉淀，两者都要能被玩具档案直接引用。
void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('建库后就有预置工序，且第一项是「整件」', () async {
    final items = await f.processes.listAll();
    expect(items.length, Defaults.builtinProcesses.length);
    expect(items.first.name, Defaults.defaultProcess);
    expect(items.every((item) => item.isBuiltin), isTrue);
    expect(items.map((item) => item.name), containsAll(['缝头', '包装', '质检']));
  });

  test('新增自定义工序后能查到，并且排在预置项之后', () async {
    final saved = await f.processes.addCustom('打眼');
    expect(saved, '打眼');

    final items = await f.processes.listAll();
    expect(items.length, Defaults.builtinProcesses.length + 1);
    expect(items.last.name, '打眼');
    expect(items.last.isBuiltin, isFalse);
    expect(items.last.badge, '自定义');
  });

  test('重复新增同名工序不会产生重复行', () async {
    await f.processes.addCustom('打眼');
    final again = await f.processes.addCustom('  打眼  ');
    expect(again, '打眼');

    final items = await f.processes.listAll();
    expect(items.where((item) => item.name == '打眼').length, 1);
  });

  test('和预置项重名时视为选中已有项，不重复插入', () async {
    final saved = await f.processes.addCustom('缝头');
    expect(saved, '缝头');

    final items = await f.processes.listAll();
    expect(items.where((item) => item.name == '缝头').length, 1);
    expect(
      items.firstWhere((item) => item.name == '缝头').isBuiltin,
      isTrue,
      reason: '不能被降级成自定义项',
    );
  });

  test('空名或过长的工序名被拒绝', () async {
    expect(
      () => f.processes.addCustom('   '),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => f.processes.addCustom('一' * (Limits.maxProcessNameLength + 1)),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('新增的工序可以立刻用来建玩具档案', () async {
    final process = await f.processes.addCustom('烫标');
    final toy = await f.toys.create(
      name: '小熊',
      process: process,
      unitPriceTenThousandth: 3500,
    );
    expect(toy.process, '烫标');
    expect(toy.displayName, '小熊 / 烫标');
  });

  test('预置工序不能删除', () async {
    expect(
      () => f.processes.removeCustom(Defaults.defaultProcess),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('已被玩具档案引用的自定义工序不能删除', () async {
    await f.processes.addCustom('烫标');
    await f.toys.create(
      name: '小熊',
      process: '烫标',
      unitPriceTenThousandth: 3000,
    );
    expect(
      () => f.processes.removeCustom('烫标'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('没被引用的自定义工序可以删除', () async {
    await f.processes.addCustom('打错了');
    await f.processes.removeCustom('打错了');
    final names = await f.processes.listNames();
    expect(names, isNot(contains('打错了')));
  });

  test('ensureSeeded 可以重复执行，不会产生重复行', () async {
    await f.processes.ensureSeeded();
    await f.processes.ensureSeeded();
    final items = await f.processes.listAll();
    expect(items.length, Defaults.builtinProcesses.length);
  });
}
