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
    this.settledCents = 0,
    this.settledCount = 0,
    this.recordCount = 0,
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

  /// 已结算金额（分）：逐笔判断「这一笔是否已结算」后累加。
  ///
  /// 与按月份估算的区别：整月标记 + 单笔取消的组合也能算准，
  /// 不会出现「金额已经变了、状态还停在旧值」的对不上。
  final int settledCents;

  /// 已结算笔数（计件 + 调整项）。
  final int settledCount;

  /// 有账笔数（计件 + 调整项），用于判定「全部结清」。
  final int recordCount;

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
  ///
  /// 按笔数判定：只要还有一笔没结，就不算结清，
  /// 这样「整月已标 + 后来补录了一笔」也会立刻退回「部分已结」。
  SettlementStatus get settlementStatus => SettlementRules.statusOfCounts(
        total: recordCount,
        settled: settledCount,
      );

  /// 未结算笔数。
  int get unsettledCount => recordCount - settledCount;

  /// 未结算金额（分），保证「已结算 + 未结算 == 应付」。
  int get unsettledCents => SettlementRules.unsettledCentsOf(netCents, settledCents);

  /// 是否整个区间都已结清。
  bool get isFullySettled => settlementStatus.isFullySettled;

  /// 有没有任何一笔已经结算（含整月标记带来的结算）。
  bool get anySettled => settledCount > 0;
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

  /// 已结算金额（分）：逐笔累加每个人已结的那部分。
  ///
  /// 逐笔结算之后不能再"只算结清的人"，否则「部分已结」的钱会整笔消失，
  /// 汇总卡的已结/未结两块就对不上台账了。
  int get settledTotalCents =>
      workers.fold(0, (sum, w) => sum + w.settledCents);

  /// 未结算金额（分）= 应付合计 - 已结算，恒等式天然成立。
  int get unsettledTotalCents => totalNetCents - settledTotalCents;

  int get settledWorkerCount => workers.where((w) => w.isFullySettled).length;

  int get unsettledWorkerCount =>
      workers.where((w) => !w.isFullySettled).length;

  /// 已结算笔数 / 总笔数：给「逐笔结算」提供进度感。
  int get settledRecordCount =>
      workers.fold(0, (sum, w) => sum + w.settledCount);

  int get totalRecordCount =>
      workers.fold(0, (sum, w) => sum + w.recordCount);

  /// 按状态筛人；`null` = 全部。
  ///
  /// 「未结算」筛选项要**连部分已结的人一起给**：
  /// 逐笔结算之后，部分已结会很常见，而这些人恰恰还欠着钱；
  /// 如果按严格相等过滤，筛选条上写着「未结算 3 人」、列表里却只剩 1 人。
  List<WorkerSettlement> filterBy(SettlementStatus? status) {
    if (status == null) return workers;
    if (status == SettlementStatus.unsettled) {
      return workers.where((w) => !w.isFullySettled).toList(growable: false);
    }
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
