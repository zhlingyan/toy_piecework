import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/data/models/settlement.dart';
import 'package:toy_piecework/domain/rules/worker_sort.dart';

/// 排序纯函数：只改顺序、不改集合，三种口径与空值边界。
void main() {
  WorkerSettlement w(String id, String code, String name, int cents) =>
      WorkerSettlement(
        workerId: id,
        workerCode: code,
        workerName: name,
        isArchived: false,
        groups: const [],
        adjustmentTotals: const {},
        pieceCents: cents,
        recordCount: 1,
        settledCount: 0,
      );

  List<String> codesOf(List<WorkerSettlement> list) =>
      list.map((item) => item.workerCode).toList();

  test('按工号用自然序：002 / 010 / A2 / A10', () {
    final input = [
      w('w4', 'A10', '赵六', 100),
      w('w3', 'A2', '王五', 100),
      w('w2', '010', '李四', 100),
      w('w1', '002', '张三', 100),
    ];
    final sorted = sortWorkers(input, sort: WorkerSort.byCode);
    expect(codesOf(sorted), ['002', '010', 'A2', 'A10']);
  });

  test('空工号排末尾，空列表 / 单元素都安全', () {
    final input = [
      w('w1', '', '无号', 100),
      w('w2', 'A10', '王五', 100),
      w('w3', 'A2', '李四', 100),
    ];
    expect(codesOf(sortWorkers(input, sort: WorkerSort.byCode)),
        ['A2', 'A10', '']);
    expect(sortWorkers(const [], sort: WorkerSort.byCode), isEmpty);
    expect(sortWorkers([input.first], sort: WorkerSort.byAmount),
        [input.first]);
  });

  test('按金额 / 总付：降序与升序互为逆序', () {
    final input = [
      w('w1', 'W001', '张三', 100),
      w('w2', 'W002', '李四', 300),
      w('w3', 'W003', '王五', 200),
    ];
    final desc = sortWorkers(input, sort: WorkerSort.byAmount);
    final asc = sortWorkers(
      input,
      sort: WorkerSort.byAmount,
      amountDesc: false,
    );
    expect(desc.map((e) => e.netCents), [300, 200, 100]);
    expect(asc.map((e) => e.netCents), [100, 200, 300]);
  });

  test('按人名按拼音首字母排：李四 / 王五 / 张三', () {
    final input = [
      w('w1', 'W001', '张三', 100),
      w('w2', 'W002', '王五', 100),
      w('w3', 'W003', '李四', 100),
    ];
    expect(
      sortWorkers(input, sort: WorkerSort.byName)
          .map((e) => e.workerName)
          .toList(),
      ['李四', '王五', '张三'],
    );
  });

  test('排序只改顺序，不增删任何元素，也不改原列表', () {
    final input = [
      w('w1', 'A10', '张三', 100),
      w('w2', 'A2', '李四', 200),
      w('w3', '002', '王五', 300),
    ];
    final sorted = sortWorkers(input, sort: WorkerSort.byCode);
    expect(sorted.length, input.length);
    expect(sorted.map((e) => e.workerId).toSet(),
        input.map((e) => e.workerId).toSet());
    expect(input.map((e) => e.workerCode).toList(), ['A10', 'A2', '002'],
        reason: '原列表不能被原地改掉');
  });
}
