import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../domain/rules/lock_rules.dart';
import '../../domain/rules/trash_rules.dart';
import '../db/app_database.dart';
import '../models/adjustment.dart';
import '../models/worker.dart';

/// 调整项仓储：补贴 / 计时 / 扣款 / 预支。
///
/// 金额恒存正数，方向由类型决定；备注必填，方便月底和工人对账。
class AdjustmentRepository {
  AdjustmentRepository(this._db);

  final AppDatabase _db;

  Future<T> _run<T>(
    DatabaseExecutor? ex,
    Future<T> Function(DatabaseExecutor executor) action,
  ) {
    if (ex != null) return action(ex);
    return _db.transaction((txn) => action(txn));
  }

  Future<Adjustment> create({
    required String date,
    required Worker worker,
    required AdjustmentType type,
    required int amountCents,
    required String remark,
    String? adjustmentId,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      if (!Dates.isValidYmd(date)) {
        throw const ValidationFailure('日期格式不正确');
      }
      if (amountCents <= 0) {
        throw const ValidationFailure('金额必须大于 0（正数，方向由类型决定）');
      }
      final trimmedRemark = remark.trim();
      if (trimmedRemark.isEmpty) {
        throw const ValidationFailure('请填写备注，方便月底核对');
      }
      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(date)]);

      final now = AppClock.nowMillis();
      final adjustment = Adjustment(
        id: adjustmentId ?? IdGen.next(),
        date: date,
        workerId: worker.id,
        workerNameSnapshot: worker.name,
        type: type,
        amountCents: amountCents,
        remark: trimmedRemark,
        deletedAt: null,
        createdAt: now,
        updatedAt: now,
      );
      final rowId = await executor.insert(
        Tables.adjustments,
        adjustment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (rowId == 0) {
        final existing = await findById(adjustment.id, ex: executor);
        if (existing != null) return existing;
        throw const ValidationFailure('保存失败，请重试');
      }
      return adjustment;
    });
  }

  Future<Adjustment> update({
    required Adjustment existing,
    int? amountCents,
    String? remark,
    String? date,
    AdjustmentType? type,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      if (existing.isDeleted) {
        throw const ValidationFailure('已删除的记录不能修改，请先从回收站恢复');
      }
      final current = await findById(existing.id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该调整项已不存在');
      }
      final newDate = date ?? current.date;
      if (!Dates.isValidYmd(newDate)) {
        throw const ValidationFailure('日期格式不正确');
      }
      final newAmount = amountCents ?? current.amountCents;
      if (newAmount <= 0) {
        throw const ValidationFailure('金额必须大于 0');
      }
      final newRemark = (remark ?? current.remark).trim();
      if (newRemark.isEmpty) {
        throw const ValidationFailure('请填写备注，方便月底核对');
      }
      await MonthLockGuard.assertRangeEditable(
        executor,
        originalDate: current.date,
        targetDate: newDate,
      );

      final updated = current.copyWith(
        date: newDate,
        type: type ?? current.type,
        amountCents: newAmount,
        remark: newRemark,
        updatedAt: AppClock.nowMillis(),
      );
      await executor.update(
        Tables.adjustments,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    });
  }

  Future<void> softDelete(String id, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final current = await findById(id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该调整项已不存在');
      }
      if (current.isDeleted) return;
      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(current.date)]);
      final now = AppClock.nowMillis();
      await executor.update(
        Tables.adjustments,
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  Future<Adjustment> restore(String id, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final current = await findById(id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该调整项已不存在');
      }
      if (!current.isDeleted) {
        throw const ValidationFailure('该调整项未被删除，无需恢复');
      }
      if (!TrashPolicy.canRestore(current.deletedAt)) {
        throw const TrashExpiredFailure();
      }
      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(current.date)]);
      final now = AppClock.nowMillis();
      await executor.update(
        Tables.adjustments,
        {'deleted_at': null, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return current.copyWith(clearDeletedAt: true, updatedAt: now);
    });
  }

  Future<Adjustment?> findById(String id, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.adjustments,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Adjustment.fromMap(rows.first);
  }

  Future<List<Adjustment>> listRange(
    DateRange range, {
    String? workerId,
    bool includeDeleted = false,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final where = <String>['date >= ?', 'date <= ?'];
    final args = <Object?>[range.start, range.end];
    if (!includeDeleted) where.add('deleted_at IS NULL');
    if (workerId != null) {
      where.add('worker_id = ?');
      args.add(workerId);
    }
    final rows = await executor.query(
      Tables.adjustments,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Adjustment.fromMap).toList(growable: false);
  }

  Future<List<Adjustment>> listTrash({
    bool includeExpired = false,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final where = <String>['deleted_at IS NOT NULL'];
    final args = <Object?>[];
    if (!includeExpired) {
      where.add('deleted_at >= ?');
      args.add(TrashPolicy.cutoffMillis());
    }
    final rows = await executor.query(
      Tables.adjustments,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'deleted_at DESC',
    );
    return rows.map(Adjustment.fromMap).toList(growable: false);
  }
}
