import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../db/app_database.dart';
import '../models/locked_month.dart';

/// 月度锁账仓储。锁账后该月增删改与回收站恢复全部被拦截。
class MonthLockRepository {
  MonthLockRepository(this._db);

  final AppDatabase _db;

  Future<List<LockedMonth>> listAll({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(Tables.lockedMonths, orderBy: 'month DESC');
    return rows.map(LockedMonth.fromMap).toList(growable: false);
  }

  Future<Set<String>> lockedMonths({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.lockedMonths,
      columns: ['month'],
      where: 'is_locked = 1',
    );
    return rows.map((row) => row['month']! as String).toSet();
  }

  Future<bool> isLocked(String month, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.lockedMonths,
      where: 'month = ? AND is_locked = 1',
      whereArgs: [month],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 锁账。重复锁同一月视为幂等。
  Future<void> lock(String month, {DatabaseExecutor? ex}) async {
    if (!Dates.isValidYm(month)) {
      throw ArgumentError('月份格式错误: $month');
    }
    final executor = ex ?? _db.raw;
    final now = AppClock.nowMillis();
    await executor.insert(
      Tables.lockedMonths,
      {
        'month': month,
        'is_locked': 1,
        'locked_at': now,
        'unlocked_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 解锁（界面需二次确认）。
  Future<void> unlock(String month, {DatabaseExecutor? ex}) async {
    if (!Dates.isValidYm(month)) {
      throw ArgumentError('月份格式错误: $month');
    }
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.lockedMonths,
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await executor.update(
      Tables.lockedMonths,
      {'is_locked': 0, 'unlocked_at': AppClock.nowMillis()},
      where: 'month = ?',
      whereArgs: [month],
    );
  }

  /// 结算页批量锁账（一次锁多个月）。
  Future<void> lockAll(Iterable<String> months, {DatabaseExecutor? ex}) async {
    final list = months.toSet().toList(growable: false);
    if (list.isEmpty) {
      throw const ValidationFailure('没有可锁账的月份');
    }
    for (final month in list) {
      await lock(month, ex: ex);
    }
  }
}
