/// 结算状态判定。
///
/// 只在一个地方定义口径，避免「列表显示已结算、明细显示未结算」这种对不上的情况。
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

  /// 按「有账的月份」判断状态。
  ///
  /// 只看这些月份，而不是区间覆盖的所有月份：比如跨 6~7 月结算，
  /// 工人 7 月没干活，不能因为 7 月没标记就永远显示「部分已结」。
  static SettlementStatus statusOf({
    required Iterable<String> months,
    required Set<String> settledMonths,
  }) {
    final list = months.toSet().toList(growable: false);
    if (list.isEmpty) return SettlementStatus.unsettled;
    final settled = list.where(settledMonths.contains).length;
    if (settled == 0) return SettlementStatus.unsettled;
    if (settled == list.length) return SettlementStatus.settled;
    return SettlementStatus.partial;
  }

  /// 已结算部分金额（分）。按月份归属拆分，逐月整数相加。
  static int settledCents(
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
  static int unsettledCents(
    Map<String, int> monthNetCents,
    Set<String> settledMonths,
    int netCents,
  ) =>
      netCents - settledCents(monthNetCents, settledMonths);

  /// 是否有任何一个月已结算。
  static bool anySettled(Set<String> settledMonths) => settledMonths.isNotEmpty;
}
