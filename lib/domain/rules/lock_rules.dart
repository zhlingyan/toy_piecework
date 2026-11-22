import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';

/// 锁账统一守门。
///
/// 所有写入路径（新增 / 修改 / 删除 / 回收站恢复 / 改期）必须先过这里，
/// 严禁各页面自行判断——尤其「跨月改日期」必须同时校验原月份与目标月份。
class MonthLockGuard {
  MonthLockGuard._();

  static Future<Set<String>> lockedMonthsIn(
    DatabaseExecutor ex,
    Iterable<String> months,
  ) async {
    final list = months
        .where(Dates.isValidYm)
        .map((month) => month)
        .toSet()
        .toList(growable: false);
    if (list.isEmpty) return <String>{};

    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await ex.query(
      Tables.lockedMonths,
      columns: ['month'],
      where: 'month IN ($placeholders) AND is_locked = 1',
      whereArgs: list,
    );
    return rows.map((row) => row['month']! as String).toSet();
  }

  static Future<bool> isLocked(DatabaseExecutor ex, String month) async {
    final locked = await lockedMonthsIn(ex, [month]);
    return locked.isNotEmpty;
  }

  /// 任一月份锁定即抛出 [LockedMonthFailure]。
  static Future<void> assertEditable(
    DatabaseExecutor ex,
    Iterable<String> months,
  ) async {
    final locked = await lockedMonthsIn(ex, months);
    if (locked.isNotEmpty) {
      throw LockedMonthFailure(locked.toList()..sort());
    }
  }

  /// 单条记录写操作：把原日期与目标日期合并校验。
  ///
  /// [originalDate] 为 null 表示新增。
  static Future<void> assertRangeEditable(
    DatabaseExecutor ex, {
    String? originalDate,
    String? targetDate,
  }) async {
    final months = <String>{
      if (originalDate != null && Dates.isValidYmd(originalDate))
        Dates.ymOfYmd(originalDate),
      if (targetDate != null && Dates.isValidYmd(targetDate))
        Dates.ymOfYmd(targetDate),
    };
    await assertEditable(ex, months);
  }
}
