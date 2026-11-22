/// 单人单月的结算标记。
///
/// 只记录「这个人的这个月工资发没发」，不复制任何金额：
/// 金额始终由计件与调整项现算，标记只影响状态与筛选，
/// 因此补录、改价之后不会出现「标记里的数字和账本对不上」。
class SettlementMark {
  const SettlementMark({
    required this.workerId,
    required this.month,
    required this.isSettled,
    required this.settledAt,
    required this.updatedAt,
  });

  factory SettlementMark.fromMap(Map<String, Object?> map) {
    return SettlementMark(
      workerId: map['worker_id']! as String,
      month: map['month']! as String,
      isSettled: (map['is_settled'] as int? ?? 0) == 1,
      settledAt: map['settled_at'] as int?,
      updatedAt: map['updated_at']! as int,
    );
  }

  final String workerId;

  /// `YYYY-MM`。
  final String month;

  final bool isSettled;

  /// 最近一次标记为已结算的时间；取消标记后为 null。
  final int? settledAt;

  final int updatedAt;

  /// 组合键：`workerId|month`，仓储层与界面共用一个口径。
  static String keyOf(String workerId, String month) => '$workerId|$month';

  String get key => keyOf(workerId, month);
}
