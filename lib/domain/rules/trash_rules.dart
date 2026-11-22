import '../../core/clock.dart';
import '../../core/constants.dart';

/// 回收站策略：删除 30 天内可恢复；超期仅在 UI 隐藏且禁止恢复，
/// 数据库保留 `deleted_at` 不物理删除（便于对账追溯）。
class TrashPolicy {
  TrashPolicy._();

  static Duration get retention => const Duration(days: Limits.trashRetentionDays);

  /// [deletedAt] 为毫秒时间戳。
  static bool canRestore(int? deletedAt, {DateTime? now}) {
    if (deletedAt == null) return false;
    final current = now ?? AppClock.now();
    final deletedAtTime = DateTime.fromMillisecondsSinceEpoch(deletedAt);
    return current.difference(deletedAtTime) <= retention;
  }

  /// 未超期的下界时间戳：`deleted_at >= cutoff` 即可恢复。
  static int cutoffMillis({DateTime? now}) {
    final current = now ?? AppClock.now();
    return current.subtract(retention).millisecondsSinceEpoch;
  }

  /// 剩余可恢复天数（用于 UI 提示）。
  static int remainingDays(int deletedAt, {DateTime? now}) {
    final current = now ?? AppClock.now();
    final deletedAtTime = DateTime.fromMillisecondsSinceEpoch(deletedAt);
    final left = retention - current.difference(deletedAtTime);
    return left.isNegative ? 0 : left.inDays;
  }
}
