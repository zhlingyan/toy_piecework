import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../db/app_database.dart';
import 'settlement_mark_repository.dart';

/// 逐笔结算仓储：把「哪一笔的钱已经发了」记到流水自己身上。
///
/// ## 为什么还要保留「人 + 月」的整月标记
///
/// 车间里的真实动作是"这个月发完了"，一笔一笔点太慢。所以两层并存：
/// * 整月标记 = 粗粒度快捷方式，一次覆盖整月（含之后补录的）；
/// * 单笔标记 = 细粒度覆盖，用于"这个人先结了 3 笔"、"这笔算错了先不给"。
///
/// 判定时取并集（`settled_at 非空 OR 整月已标`），所以升级前后金额与状态一致。
///
/// ## 三态问题怎么绕开的
///
/// 只有 `settled_at` 一个字段，天然表达不了"整月已结、但这一笔未结"。
/// 解决办法是**展开**：取消某一笔时，若所在月有整月标记，
/// 先把整月标记落到每一笔（写 `settled_at`），再清掉整月标记，
/// 最后把这笔置空。结果与"整月已结、这一笔例外"完全等价，且只有两态。
///
/// 结算**不经过锁账校验**：锁账防改账，结算记"钱发没发"，
/// 发完钱锁了账之后补标记不该被拦。
class SettlementEntryRepository {
  SettlementEntryRepository(this._db, this._marks);

  final AppDatabase _db;
  final SettlementMarkRepository _marks;

  /// 单笔标记 / 取消计件流水。
  Future<void> setRecordSettled(
    String id, {
    required bool settled,
  }) =>
      _apply(
        table: Tables.pieceRecords,
        id: id,
        settled: settled,
        label: '计件流水',
      );

  /// 单笔标记 / 取消调整项。
  Future<void> setAdjustmentSettled(
    String id, {
    required bool settled,
  }) =>
      _apply(
        table: Tables.adjustments,
        id: id,
        settled: settled,
        label: '调整项',
      );

  Future<void> _apply({
    required String table,
    required String id,
    required bool settled,
    required String label,
  }) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['worker_id', 'date', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ValidationFailure('该$label已不存在');
      }
      final row = rows.first;
      if (row['deleted_at'] != null) {
        throw ValidationFailure('已删除的$label不能标记结算，请先从回收站恢复');
      }
      final workerId = row['worker_id']! as String;
      final date = row['date']! as String;
      final month = Dates.ymOfYmd(date);
      final now = AppClock.nowMillis();

      if (!settled && await _marks.isSettled(workerId, month, ex: txn)) {
        // 整月标记会把这笔也覆盖成"已结算"，所以先展开成逐笔标记，
        // 否则取消完还显示已结算，用户会以为没生效。
        await txn.update(
          table,
          {'settled_at': now, 'updated_at': now},
          where: 'worker_id = ? AND substr(date, 1, 7) = ? '
              'AND settled_at IS NULL AND deleted_at IS NULL',
          whereArgs: [workerId, month],
        );
        await _marks.markSettled(
          workerId: workerId,
          months: [month],
          settled: false,
          ex: txn,
        );
      }

      await txn.update(
        table,
        {'settled_at': settled ? now : null, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// 整期标记 / 取消：一次覆盖一个人的这个区间。
  ///
  /// * 标记：写整月标记（顺带覆盖之后补录的账，符合"这一期发完了"的直觉）；
  /// * 取消：清掉区间内的逐笔标记 + 清掉整月标记，
  ///   否则"取消本期已结算"之后还会剩一堆单笔已结，看着像没生效。
  Future<void> markRange({
    required String workerId,
    required Iterable<String> months,
    required DateRange range,
    required bool settled,
  }) async {
    final monthList = months.toSet().toList(growable: false);
    if (monthList.isEmpty) return;
    await _db.transaction((txn) async {
      await _marks.markSettled(
        workerId: workerId,
        months: monthList,
        settled: settled,
        ex: txn,
      );
      if (settled) return;
      final now = AppClock.nowMillis();
      for (final table in [Tables.pieceRecords, Tables.adjustments]) {
        await txn.update(
          table,
          {'settled_at': null, 'updated_at': now},
          where: 'worker_id = ? AND date >= ? AND date <= ?',
          whereArgs: [workerId, range.start, range.end],
        );
      }
    });
  }

  /// 某工人所有「整月已标记结算」的月份（明细页判断单笔状态用）。
  Future<Set<String>> settledMonthsFor(String workerId) =>
      _marks.settledMonthsFor(workerId);
}
