/// 结算状态判定。
///
/// 只在一个地方定义口径，避免「列表显示已结算、明细显示未结算」这种对不上的情况。
///
/// v1.5 起支持**逐笔结算**，状态判定从「按月份」升级为「按笔数」：
/// 每一笔（计件或调整项）要么已结算、要么未结算，人的状态由这两者的比例决定。
/// 整月标记仍然有效——它等价于"这个月所有笔都已结算"，
/// 在仓储层用 `settled_at 非空 OR 整月已标记` 求并集，所以老账的状态不会变。
library;

enum SettlementStatus {
  settled('已结算'),
  partial('部分已结'),
  unsettled('未结算');

  const SettlementStatus(this.label);

  final String label;

  /// 全部有账月份都已结算。
  bool get isFullySettled => this == SettlementStatus.settled;

  /// 还有钱没结（未结算 + 部分已结）。
  bool get hasUnsettled => this != SettlementStatus.settled;
}

class SettlementRules {
  SettlementRules._();

  /// 按笔数判定：全部已结 / 部分已结 / 未结算。
  ///
  /// 用笔数而不是金额判定，是因为金额里可能有负数（预支多于计件），
  /// 拿金额比大小会把「都结清了但净额为负」判成未结算。
  /// 金额只用于展示拆分，两者互不干扰。
  static SettlementStatus statusOfCounts({
    required int total,
    required int settled,
  }) {
    if (total <= 0) return SettlementStatus.unsettled;
    if (settled <= 0) return SettlementStatus.unsettled;
    if (settled >= total) return SettlementStatus.settled;
    return SettlementStatus.partial;
  }

  /// 兼容旧口径：按「有账的月份」判断。
  ///
  /// 只在没有逐笔数据可用的地方（如工资条摘要、纯月份视图）使用；
  /// 结算页与明细页一律用 [statusOfCounts]，避免两处口径打架。
  static SettlementStatus statusOfMonths({
    required Iterable<String> months,
    required Set<String> settledMonths,
  }) {
    final list = months.toSet().toList(growable: false);
    if (list.isEmpty) return SettlementStatus.unsettled;
    final settled = list.where(settledMonths.contains).length;
    return statusOfCounts(total: list.length, settled: settled);
  }

  /// 按月份归属拆分的已结算金额（分）。逐月整数相加。
  static int settledCentsByMonth(
    Map<String, int> monthNetCents,
    Set<String> settledMonths,
  ) {
    var total = 0;
    monthNetCents.forEach((month, cents) {
      if (settledMonths.contains(month)) total += cents;
    });
    return total;
  }

  /// 未结算部分金额（分）= 合计 - 已结算。
  ///
  /// 用减法而不是重新累加，保证「已结算 + 未结算 == 应付」永远成立，
  /// 不会因为某个月份漏算而出现账目对不上。
  static int unsettledCentsOf(int netCents, int settledCents) =>
      netCents - settledCents;
}
