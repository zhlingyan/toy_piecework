import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../domain/rules/settlement_rules.dart';

/// 结算分组：严格按 (toy_id, process, 正常单价, 是否加班, 加班单价) 聚合。
///
/// 两条铁律：
/// * 同一工序中途调价（0.20 元 100 件 + 0.25 元 100 件）必然拆成两行，
///   避免出现「平均单价」这类会造成分位误差的算法；
/// * 加班与正常班必须拆行，否则两者的件数会被合并、金额按同一单价算错。
class PieceGroup {
  const PieceGroup({
    required this.toyId,
    required this.toyName,
    required this.process,
    required this.unitPriceTenThousandth,
    required this.quantity,
    required this.subtotalCents,
    this.overtime = false,
    this.overtimePriceTenThousandth = 0,
    this.overtimeMultiplier = 1000,
  });

  final String toyId;
  final String toyName;
  final String process;

  /// 正常班单价快照。
  final int unitPriceTenThousandth;
  final int quantity;
  final int subtotalCents;

  /// 是否加班行。
  final bool overtime;

  /// 加班单价快照（未加班为 0）。
  final int overtimePriceTenThousandth;

  /// 加班倍率，千分比。
  final int overtimeMultiplier;

  /// 本行实际计价的单价。
  int get pricingPriceTenThousandth =>
      overtime && overtimePriceTenThousandth > 0
          ? overtimePriceTenThousandth
          : unitPriceTenThousandth;

  /// 行标签后缀，例如 `加班 ×1.5`；正常班为空串。
  String get overtimeSuffix {
    if (!overtime) return '';
    final m = overtimeMultiplier;
    final whole = m ~/ 1000;
    var frac = (m % 1000).toString().padLeft(3, '0');
    while (frac.length > 1 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return '加班 ×$whole.$frac';
  }
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
    this.monthNetCents = const {},
    this.settledMonths = const {},
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

  /// 按月拆分的应付净额（分）：`YYYY-MM` → 金额。
  ///
  /// 结算状态是「按月」记的，所以要把金额也按月拆开，
  /// 才能算清「已结算多少、未结算多少」，而不是靠估算。
  final Map<String, int> monthNetCents;

  /// 区间内有账、且已标记结算的月份。
  final Set<String> settledMonths;

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

  /// 有账的月份（按升序），用于判定与批量标记。
  List<String> get activeMonths {
    final months = monthNetCents.keys.toList(growable: false)..sort();
    return months;
  }

  /// 本区间的结算状态：全部已结 / 部分已结 / 未结算。
  SettlementStatus get settlementStatus => SettlementRules.statusOf(
        months: activeMonths,
        settledMonths: settledMonths,
      );

  /// 已结算金额（分）。
  int get settledCents =>
      SettlementRules.settledCents(monthNetCents, settledMonths);

  /// 未结算金额（分），保证「已结算 + 未结算 == 应付」。
  int get unsettledCents =>
      SettlementRules.unsettledCents(monthNetCents, settledMonths, netCents);

  /// 是否整个区间都已结清。
  bool get isFullySettled => settlementStatus.isFullySettled;
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

  /// 已结算金额（只统计全部结清的工人）。
  ///
  /// 部分已结的工人整笔计入未结算，提醒「这个人还有月份没结」，
  /// 避免看着「已结算 800 元」就以为已经结干净了。
  int get settledTotalCents => workers
      .where((w) => w.isFullySettled)
      .fold(0, (sum, w) => sum + w.netCents);

  /// 未结算金额（含部分已结的整个人）。
  int get unsettledTotalCents => workers
      .where((w) => !w.isFullySettled)
      .fold(0, (sum, w) => sum + w.netCents);

  int get settledWorkerCount => workers.where((w) => w.isFullySettled).length;

  int get unsettledWorkerCount =>
      workers.where((w) => !w.isFullySettled).length;

  /// 按状态筛人；`null` = 全部。
  List<WorkerSettlement> filterBy(SettlementStatus? status) {
    if (status == null) return workers;
    return workers
        .where((w) => w.settlementStatus == status)
        .toList(growable: false);
  }

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
