import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/app_database.dart';
import '../models/settlement_event.dart';

/// 结算状态变更历史：只追加，不覆盖。
///
/// 与 [SettlementMarkRepository] 的分工：
/// * marks / 流水 `settled_at` = **当前状态**，会被后续操作覆盖；
/// * 本表 = **完整变更流**，只 INSERT，永不 UPDATE / DELETE。
///
/// `seq` 由 SQLite AUTOINCREMENT 生成，天然就是「第几次变更」的追加标识；
/// 备份恢复时按原 seq 写回，之后的新记录继续往后排，不会和老记录重号。
class SettlementHistoryRepository {
  SettlementHistoryRepository(this._db);

  final AppDatabase _db;

  /// 追加一条变更记录。
  ///
  /// [ex] 由调用方的事务传入：状态变更与留痕必须同生共死，
  /// 结算成功但历史没写上（或反过来）都是不能接受的。
  Future<void> append({
    required String workerId,
    required SettlementAction action,
    required SettlementEventScope scope,
    String reason = '',
    Iterable<String> months = const [],
    String rangeStart = '',
    String rangeEnd = '',
    String entryLabel = '',
    int? occurredAt,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final millis = occurredAt ?? AppClock.nowMillis();
    final monthList =
        months.where((month) => month.isNotEmpty).toSet().toList()..sort();
    await executor.insert(Tables.settlementHistory, {
      'worker_id': workerId,
      'action': action.code,
      'scope': scope.code,
      'reason': reason.trim(),
      'months': monthList.join(','),
      'range_start': rangeStart,
      'range_end': rangeEnd,
      'entry_label': entryLabel,
      'occurred_at': millis,
      'happened_at': Dates.formatMillis(millis),
    });
  }

  /// 某工人的完整变更历史，按时间倒序（最新在前）。
  Future<List<SettlementEvent>> listForWorker(
    String workerId, {
    int? limit,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.settlementHistory,
      where: 'worker_id = ?',
      whereArgs: [workerId],
      orderBy: 'seq DESC',
      limit: limit,
    );
    return rows.map(SettlementEvent.fromMap).toList(growable: false);
  }

  /// 最近一次变更（当前状态标识用）。
  Future<SettlementEvent?> latestForWorker(
    String workerId, {
    DatabaseExecutor? ex,
  }) async {
    final list = await listForWorker(workerId, limit: 1, ex: ex);
    return list.isEmpty ? null : list.first;
  }

  /// 变更次数（"第 N 次变更"用；0 表示从未有过状态变更）。
  Future<int> countForWorker(String workerId, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.settlementHistory} '
      'WHERE worker_id = ?',
      [workerId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }
}
