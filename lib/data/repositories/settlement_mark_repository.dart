import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../db/app_database.dart';
import '../models/settlement_mark.dart';

/// 结算状态仓储：按「工人 + 月份」记已结算/未结算。
///
/// 设计取舍：
/// * 状态不写进流水，避免一条一条去改几千行；
/// * 也不和锁账合并——锁账是「防改动」，结算是「钱已发」，
///   现实中经常先结算后锁账，甚至只结算不锁账；
/// * 取消标记不删行，只把 `is_settled` 置 0，留下「谁在什么时候动过」的痕迹。
class SettlementMarkRepository {
  SettlementMarkRepository(this._db);

  final AppDatabase _db;

  Future<T> _run<T>(
    DatabaseExecutor? ex,
    Future<T> Function(DatabaseExecutor executor) action,
  ) {
    if (ex != null) return action(ex);
    return _db.transaction((txn) => action(txn));
  }

  /// 某工人所有「已结算」的月份。
  Future<Set<String>> settledMonthsFor(
    String workerId, {
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.settlementMarks,
      columns: ['month'],
      where: 'worker_id = ? AND is_settled = 1',
      whereArgs: [workerId],
    );
    return rows.map((row) => row['month']! as String).toSet();
  }

  /// 批量取：`workerId|month` → 标记。结算页与明细页共用。
  Future<Map<String, SettlementMark>> byWorkerMonth({
    Iterable<String>? workerIds,
    Iterable<String>? months,
    DatabaseExecutor? ex,
  }) async {
    final ids = workerIds?.toSet().toList(growable: false);
    final monthList = months?.toSet().toList(growable: false);
    if (ids != null && ids.isEmpty) return const {};
    if (monthList != null && monthList.isEmpty) return const {};

    final executor = ex ?? _db.raw;
    final where = <String>[];
    final args = <Object?>[];
    if (ids != null) {
      where.add('worker_id IN (${List.filled(ids.length, '?').join(',')})');
      args.addAll(ids);
    }
    if (monthList != null) {
      where.add('month IN (${List.filled(monthList.length, '?').join(',')})');
      args.addAll(monthList);
    }

    final rows = await executor.query(
      Tables.settlementMarks,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
    return {
      for (final row in rows)
        if (row['is_settled'] == 1)
          SettlementMark.keyOf(
            row['worker_id']! as String,
            row['month']! as String,
          ): SettlementMark.fromMap(row),
    };
  }

  /// 批量取某工人指定月份里「已结算」的集合。
  Future<Set<String>> settledMonthsOf(
    String workerId,
    Iterable<String> months, {
    DatabaseExecutor? ex,
  }) async {
    final list = months.toSet().toList(growable: false);
    if (list.isEmpty) return const {};
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.settlementMarks,
      columns: ['month'],
      where: 'worker_id = ? AND is_settled = 1 '
          'AND month IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: [workerId, ...list],
    );
    return rows.map((row) => row['month']! as String).toSet();
  }

  Future<bool> isSettled(
    String workerId,
    String month, {
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.settlementMarks,
      where: 'worker_id = ? AND month = ? AND is_settled = 1',
      whereArgs: [workerId, month],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 标记/取消标记若干月份。月份列表为空时什么也不做（幂等）。
  Future<void> markSettled({
    required String workerId,
    required Iterable<String> months,
    required bool settled,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      final list = months.toSet().toList(growable: false);
      if (list.isEmpty) return;
      for (final month in list) {
        if (!Dates.isValidYm(month)) {
          throw ValidationFailure('月份格式不正确：$month');
        }
      }
      final now = AppClock.nowMillis();
      for (final month in list) {
        await executor.insert(
          Tables.settlementMarks,
          {
            'worker_id': workerId,
            'month': month,
            'is_settled': settled ? 1 : 0,
            'settled_at': settled ? now : null,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 批量标记多个工人（结算页全选时用），一个事务内完成。
  Future<void> markMany({
    required Iterable<String> workerIds,
    required Iterable<String> months,
    required bool settled,
    DatabaseExecutor? ex,
  }) async {
    final ids = workerIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    await _run(ex, (executor) async {
      for (final workerId in ids) {
        await markSettled(
          workerId: workerId,
          months: months,
          settled: settled,
          ex: executor,
        );
      }
    });
  }
}
