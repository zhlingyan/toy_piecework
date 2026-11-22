import '../../core/dates.dart';

/// 「今天补录了前面日期的内容」的判定。
///
/// 这里要严格区分两个时间：
/// * **业务日期**（`workDate`，库里叫 `date`）：这笔活算哪一天的账，
///   所有统计/结算/锁账都只认它；
/// * **录入时间**（`createdAt`）：什么时候按的保存键，只用于审计。
///
/// 判定规则：录入时间的自然日 == 今天，且业务日期早于今天。
/// 两个条件同时成立才算补录——昨天录的 11 号的活不是"今天补录"，
/// 今天录今天的活也不是补录。
class BackfillRules {
  BackfillRules._();

  /// 是否是「今天添加的前面日期内容」。
  static bool isBackfill({
    required String workDate,
    required int createdAtMillis,
    required String today,
  }) {
    if (!Dates.isValidYmd(workDate) || !Dates.isValidYmd(today)) return false;
    if (workDate.compareTo(today) >= 0) return false;
    return Dates.ymdOfMillis(createdAtMillis) == today;
  }

  /// 补录提前了多少天；非补录返回 `null`。
  static int? daysEarlier({
    required String workDate,
    required int createdAtMillis,
    required String today,
  }) {
    if (!isBackfill(
      workDate: workDate,
      createdAtMillis: createdAtMillis,
      today: today,
    )) {
      return null;
    }
    return Dates.daysBetween(workDate, today);
  }

  /// 角标文案：`补录`。
  static const String badge = '补录';

  /// 一句人话说明：`今天补录，账算在 11-11`。
  static String describe({
    required String workDate,
    required int createdAtMillis,
    required String today,
  }) {
    if (!isBackfill(
      workDate: workDate,
      createdAtMillis: createdAtMillis,
      today: today,
    )) {
      return '';
    }
    return '今天补录，账算在 ${workDate.substring(5)}';
  }
}
