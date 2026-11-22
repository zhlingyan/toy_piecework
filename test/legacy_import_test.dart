import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/core/failures.dart';
import 'package:toy_piecework/core/money.dart';

import 'support/fixture.dart';

/// 一份贴近小程序旧版导出的样例：驼峰/下划线混用、缺工序、缺单价、缺 id。
const String _legacyJson = '''
{
  "workers": [
    {"id": "w1", "name": "张三", "code": "A01"}
  ],
  "records": [
    {"id": "r1", "date": "2025-06-01", "workerId": "w1", "workerName": "张三",
     "toyId": "t1", "toyName": "小熊", "process": "", "quantity": 100,
     "unitPrice": 0.2, "remark": "首批"},
    {"id": "r2", "date": "2025-06-02", "workerId": "w1", "toyId": "t9",
     "toyName": "小熊", "quantity": 50, "unit_price_ten_thousandth": 2500},
    {"id": "r3", "date": "2025-06-03", "workerId": "w2", "workerName": "李四",
     "toyName": "积木", "quantity": 10, "subtotal": 3.5}
  ]
}
''';

void main() {
  late Fixture f;

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  test('预览：笔数、日期跨度、待导入数', () async {
    final preview = await f.legacy.inspect(_legacyJson);
    expect(preview.recordCount, 3);
    expect(preview.willImport, 3);
    expect(preview.skippedExisting, 0);
    expect(preview.minDate, '2025-06-01');
    expect(preview.maxDate, '2025-06-03');
    expect(preview.workerCount, 2);
    expect(preview.toyCount, 3, reason: 't1 与 t9 是两个不同玩具 id，另加自动补建的积木');
  });

  test('导入保留原 id / 单价 / 小计，缺失工序默认整件', () async {
    final result = await f.legacy.import(_legacyJson);
    expect(result.inserted, 3);
    expect(result.createdWorkers, 2);
    expect(result.createdToys, 3);

    final records = await f.records.listRange(
      DateRange.of('2025-06-01', '2025-06-30'),
    );
    expect(records.length, 3);

    final r1 = records.firstWhere((r) => r.id == 'r1');
    expect(r1.processSnapshot, '整件');
    expect(r1.unitPriceSnapshot, 2000);
    expect(r1.subtotalCents, 2000);
    expect(Money.formatCents(r1.subtotalCents), '20.00');

    final r2 = records.firstWhere((r) => r.id == 'r2');
    expect(r2.unitPriceSnapshot, 2500);
    expect(r2.subtotalCents, 1250);

    final r3 = records.firstWhere((r) => r.id == 'r3');
    expect(r3.subtotalCents, 350, reason: '小计保持原值 3.50 元');
  });

  test('缺失档案自动补建为归档状态', () async {
    await f.legacy.import(_legacyJson);
    final workers = await f.workers.listAll();
    expect(workers.length, 2);
    expect(workers.every((w) => w.isArchived), isTrue,
        reason: '旧账补建的人不应出现在录入列表');

    // 录入页（启用）应为空，但历史仍可查
    expect(await f.workers.listActive(), isEmpty);
    final settlement = await f.settlements.settle(
      DateRange.of('2025-06-01', '2025-06-30'),
    );
    expect(settlement.workers.length, 2);
  });

  test('重复导入新增 0 笔（验收用例 5）', () async {
    final first = await f.legacy.import(_legacyJson);
    expect(first.inserted, 3);

    final second = await f.legacy.import(_legacyJson);
    expect(second.inserted, 0);
    expect(second.skippedExisting, 3);
    expect(second.createdWorkers, 0);
    expect(second.createdToys, 0);

    final records = await f.records.listRange(
      DateRange.of('2025-06-01', '2025-06-30'),
    );
    expect(records.length, 3);
  });

  test('已锁月份跳过导入并计数', () async {
    await f.months.lock('2025-06');
    final preview = await f.legacy.inspect(_legacyJson);
    expect(preview.willImport, 0);
    expect(preview.skippedLocked, 3);

    final result = await f.legacy.import(_legacyJson);
    expect(result.inserted, 0);
    expect(result.skippedLocked, 3);
  });

  test('没有 id 的记录：两次导入仍然幂等', () async {
    const noIdJson = '''
    {"records": [
      {"date": "2025-07-01", "workerName": "王五", "toyName": "陀螺",
       "quantity": 12, "unitPrice": 0.5}
    ]}
    ''';
    final first = await f.legacy.import(noIdJson);
    expect(first.inserted, 1);
    final second = await f.legacy.import(noIdJson);
    expect(second.inserted, 0);
    expect(second.skippedExisting, 1);
  });

  test('损坏 / 结构不符的文件给出中文提示', () async {
    expect(
      () => f.legacy.inspect('not a json'),
      throwsA(isA<LegacyImportFailure>()),
    );
    expect(
      () => f.legacy.inspect('{"foo": 1}'),
      throwsA(isA<LegacyImportFailure>()),
    );
    expect(
      () => f.legacy.inspect('{"records": []}'),
      throwsA(isA<LegacyImportFailure>()),
    );
  });

  test('缺少日期或数量的行被跳过并计入 skippedInvalid', () async {
    const dirtyJson = '''
    {"records": [
      {"id": "ok1", "date": "2025-08-01", "workerName": "甲", "toyName": "球",
       "quantity": 5, "unitPrice": 1},
      {"id": "bad1", "workerName": "乙", "toyName": "球", "quantity": 5},
      {"id": "bad2", "date": "2025-08-02", "workerName": "丙", "toyName": "球"}
    ]}
    ''';
    final result = await f.legacy.import(dirtyJson);
    expect(result.inserted, 1);
    expect(result.preview.skippedInvalid, 2);
  });

  test('兼容数组根节点与嵌套 data 结构', () async {
    const arrayRoot = '''
    [{"id": "a1", "date": "2025-09-01", "workerName": "丁", "toyName": "车",
      "quantity": 1, "unitPrice": 2}]
    ''';
    final r1 = await f.legacy.import(arrayRoot);
    expect(r1.inserted, 1);

    const nested = '''
    {"data": {"piece_records": [
      {"id": "n1", "date": "2025-09-02", "workerName": "戊", "toyName": "车",
       "quantity": 2, "unit_price": 1.5}
    ]}}
    ''';
    final r2 = await f.legacy.import(nested);
    expect(r2.inserted, 1);
    final record = await f.records.findById('n1');
    expect(record!.unitPriceSnapshot, 15000);
    expect(record.subtotalCents, 300);
  });
}
