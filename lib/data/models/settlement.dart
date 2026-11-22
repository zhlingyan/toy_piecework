import '../../core/constants.dart';
import '../../core/dates.dart';

/// 结算分组：严格按 (toy_id, process_snapshot, unit_price_snapshot) 聚合。
///
/// 同一工序中途调价（0.20 元 100 件 + 0.25 元 100 件）必然拆成两行，
/// 避免出现「平均单价」这类会造成分位误差的算法。
class PieceGroup {
  const PieceGroup({
    required this.toyId,
    required this.toyName,
    required this.process,
    required this.unitPriceTenThousandth,
    required this.quantity,
    required this.subtotalCents,
  });

  final String toyId;
  final String toyName;
  final String process;
  final int unitPriceTenThousandth;
  final int quantity;
  final int subtotalCents;
}

/// 单个工人在某区间的结算结果。
class WorkerSettlement {
  const WorkerSettlement({
    required this.workerId,
    required this.workerCode,
    required this.workerName,
    required this.isArchived,
    required this.groups,
    required this.adjustmentTotals,
    required this.pieceCents,
  });

  final String workerId;
  final String workerCode;
  final String workerName;
  final bool isArchived;

  /// 已分组的计件明细。
  final List<PieceGroup> groups;

  /// 各类型调整项金额（正数）。
  final Map<AdjustmentType, int> adjustmentTotals;

  /// 计件工资合计（分）。
  final int pieceCents;

  int get bonusCents => adjustmentTotals[AdjustmentType.bonus] ?? 0;
  int get hourlyCents => adjustmentTotals[AdjustmentType.hourly] ?? 0;
  int get deductionCents => adjustmentTotals[AdjustmentType.deduction] ?? 0;
  int get advanceCents => adjustmentTotals[AdjustmentType.advance] ?? 0;

  /// 应付 = 计件 + 补贴 + 计时 - 扣款 - 预支。
  int get netCents => pieceCents + bonusCents + hourlyCents - deductionCents - advanceCents;

  /// 应付为负：原值显示并标红提示核对。
  bool get isNegative => netCents < 0;

  /// 仅为调整项的工人（计件为 0）也必须出现在结算清单里。
  bool get onlyAdjustments => groups.isEmpty && pieceCents == 0;

  int get totalQuantity => groups.fold(0, (sum, g) => sum + g.quantity);

  int get adjustmentCount =>
      adjustmentTotals.values.where((amount) => amount > 0).length;

  bool get hasAdjustments => bonusCents + hourlyCents + deductionCents + advanceCents > 0;
}

/// 一个区间的完整结算结果。
class SettlementResult {
  const SettlementResult({
    required this.range,
    required this.workers,
    required this.recordCount,
  });

  final DateRange range;

  /// 按计件额倒序、再按姓名排序。
  final List<WorkerSettlement> workers;

  /// 参与结算的流水笔数（不含已删除）。
  final int recordCount;

  int get totalPieceCents =>
      workers.fold(0, (sum, w) => sum + w.pieceCents);

  int get totalNetCents => workers.fold(0, (sum, w) => sum + w.netCents);

  int get bonusTotal => workers.fold(0, (sum, w) => sum + w.bonusCents);
  int get hourlyTotal => workers.fold(0, (sum, w) => sum + w.hourlyCents);
  int get deductionTotal => workers.fold(0, (sum, w) => sum + w.deductionCents);
  int get advanceTotal => workers.fold(0, (sum, w) => sum + w.advanceCents);

  int get workerCount => workers.length;

  bool get isEmpty => workers.isEmpty;
}

/// 概览页统计。
class DayOverview {
  const DayOverview({
    required this.date,
    required this.recordCount,
    required this.workerCount,
    required this.pieceCents,
    required this.adjustmentCount,
  });

  final String date;
  final int recordCount;

  /// 出勤人数（当天有计件或有调整项的工人数）。
  final int workerCount;

  /// 当日计件总额（分）。
  final int pieceCents;

  final int adjustmentCount;
}
