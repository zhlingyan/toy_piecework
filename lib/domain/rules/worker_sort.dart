import '../../data/models/settlement.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import 'natural_sort.dart';

/// 「按工人结算」的三种排序口径。
enum WorkerSort {
  byName('按人名'),
  byCode('按工号'),
  byAmount('按金额 / 总付');

  const WorkerSort(this.label);

  final String label;
}

/// 对工人列表排序的**纯函数**：只改顺序，不增删任何元素。
///
/// 管线固定为 `状态筛选 → 查找过滤 → 本函数排序`，所以这里拿到的
/// 已经是筛完的集合；排序绝不能偷偷改变人数，否则汇总与列表会对不上。
///
/// 稳定兜底键：拼音首字母 → 姓名自然序 → 工号自然序 → workerId，
/// 保证同金额 / 同名 / 同工号时顺序也可预期，不会每次刷新乱跳。
/// 空工号一律排到末尾（没编工号的人不该挡在 W001 前面）。
List<WorkerSettlement> sortWorkers(
  List<WorkerSettlement> input, {
  required WorkerSort sort,
  bool amountDesc = true,
}) {
  final list = input.toList(growable: true);
  list.sort((a, b) {
    switch (sort) {
      case WorkerSort.byAmount:
        final byAmount = a.netCents.compareTo(b.netCents);
        if (byAmount != 0) return amountDesc ? -byAmount : byAmount;
        break;
      case WorkerSort.byCode:
        final ac = a.workerCode.trim();
        final bc = b.workerCode.trim();
        if (ac.isEmpty != bc.isEmpty) return ac.isEmpty ? 1 : -1;
        if (ac.isNotEmpty) {
          final byCode = naturalCompare(ac, bc);
          if (byCode != 0) return byCode;
        }
        break;
      case WorkerSort.byName:
        // 主键就是下面的「首字母 + 姓名」，直接进入兜底链。
        break;
    }

    final initialsA = PinyinHelper.initialsOf(a.workerName).toLowerCase();
    final initialsB = PinyinHelper.initialsOf(b.workerName).toLowerCase();
    final byInitials = initialsA.compareTo(initialsB);
    if (byInitials != 0) return byInitials;

    final byName = naturalCompare(a.workerName, b.workerName);
    if (byName != 0) return byName;

    final byCode = naturalCompare(a.workerCode, b.workerCode);
    if (byCode != 0) return byCode;

    return a.workerId.compareTo(b.workerId);
  });
  return list;
}
