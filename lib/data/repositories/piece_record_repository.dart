import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../core/money.dart';
import '../../domain/rules/lock_rules.dart';
import '../../domain/rules/trash_rules.dart';
import '../db/app_database.dart';
import '../models/piece_record.dart';
import '../models/toy.dart';
import '../models/worker.dart';

/// 计件流水仓储。
///
/// 三条铁律：
/// 1. 任何写入前先过 [MonthLockGuard]（锁账不可改）；
/// 2. 姓名/玩具/工序/单价一律写快照，档案后续变动不回溯历史；
/// 3. 永不物理删除，只写 `deleted_at`。
class PieceRecordRepository {
  PieceRecordRepository(this._db);

  final AppDatabase _db;

  Future<T> _run<T>(
    DatabaseExecutor? ex,
    Future<T> Function(DatabaseExecutor executor) action,
  ) {
    if (ex != null) return action(ex);
    return _db.transaction((txn) => action(txn));
  }

  /// 新增一笔计件。
  ///
  /// [recordId] 由界面在点击保存时生成，双击重复提交会因主键冲突被忽略，
  /// 从数据层根除重复入账。
  /// [unitPriceTenThousandth] 用于补录过去日期时手动填写当时单价；
  /// 不传则取档案当前单价。
  Future<PieceRecord> create({
    required String date,
    required Worker worker,
    required Toy toy,
    required int quantity,
    String remark = '',
    String? recordId,
    int? unitPriceTenThousandth,
    String? processSnapshot,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      if (!Dates.isValidYmd(date)) {
        throw const ValidationFailure('日期格式不正确');
      }
      if (quantity <= 0) {
        throw const ValidationFailure('数量必须是大于 0 的整数');
      }
      final price = unitPriceTenThousandth ?? toy.unitPriceTenThousandth;
      if (price < 0) {
        throw const ValidationFailure('单价不能为负数');
      }

      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(date)]);

      final now = AppClock.nowMillis();
      final record = PieceRecord(
        id: recordId ?? IdGen.nextRecordId(),
        date: date,
        workerId: worker.id,
        toyId: toy.id,
        workerNameSnapshot: worker.name,
        toyNameSnapshot: toy.name,
        processSnapshot: (processSnapshot?.trim().isNotEmpty ?? false)
            ? processSnapshot!.trim()
            : toy.process,
        unitPriceSnapshot: price,
        quantity: quantity,
        subtotalCents: Money.subtotalCents(
          quantity: quantity,
          priceTenThousandth: price,
        ),
        remark: remark.trim(),
        deletedAt: null,
        createdAt: now,
        updatedAt: now,
      );

      final rowId = await executor.insert(
        Tables.pieceRecords,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (rowId == 0) {
        // 主键已存在：说明是重复提交，返回已落库的那笔，保证界面一致。
        final existing = await findById(record.id, ex: executor);
        if (existing != null) return existing;
        throw const ValidationFailure('保存失败，请重试');
      }
      return record;
    });
  }

  /// 修改一笔计件。
  ///
  /// * 改数量：沿用原单价快照重算小计；
  /// * 只改备注：小计原样保留（不重新取整，避免历史分位漂移）；
  /// * 改日期：同时校验原月份与目标月份是否锁账。
  Future<PieceRecord> update({
    required PieceRecord existing,
    int? quantity,
    String? remark,
    String? date,
    int? unitPriceTenThousandth,
    String? toyId,
    String? toyNameSnapshot,
    String? processSnapshot,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      if (existing.isDeleted) {
        throw const ValidationFailure('已删除的记录不能修改，请先从回收站恢复');
      }
      final current = await findById(existing.id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该记录已不存在');
      }

      final newDate = date ?? current.date;
      if (!Dates.isValidYmd(newDate)) {
        throw const ValidationFailure('日期格式不正确');
      }
      final newQuantity = quantity ?? current.quantity;
      if (newQuantity <= 0) {
        throw const ValidationFailure('数量必须是大于 0 的整数');
      }
      final newPrice = unitPriceTenThousandth ?? current.unitPriceSnapshot;
      if (newPrice < 0) {
        throw const ValidationFailure('单价不能为负数');
      }

      // 跨月改期：原月与目标月都不许锁账
      await MonthLockGuard.assertRangeEditable(
        executor,
        originalDate: current.date,
        targetDate: newDate,
      );

      final sameQuantityAndPrice =
          newQuantity == current.quantity && newPrice == current.unitPriceSnapshot;
      final updated = current.copyWith(
        date: newDate,
        toyId: toyId,
        toyNameSnapshot: toyNameSnapshot,
        processSnapshot: processSnapshot,
        quantity: newQuantity,
        unitPriceSnapshot: newPrice,
        remark: (remark ?? current.remark).trim(),
        subtotalCents: sameQuantityAndPrice
            ? current.subtotalCents
            : Money.subtotalCents(
                quantity: newQuantity,
                priceTenThousandth: newPrice,
              ),
        updatedAt: AppClock.nowMillis(),
      );

      await executor.update(
        Tables.pieceRecords,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    });
  }

  /// 软删除，进入回收站（30 天内可恢复）。
  Future<void> softDelete(String id, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final current = await findById(id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该记录已不存在');
      }
      if (current.isDeleted) return;
      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(current.date)]);
      final now = AppClock.nowMillis();
      await executor.update(
        Tables.pieceRecords,
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  /// 回收站恢复。超过 30 天或所在月份已锁账时拒绝。
  Future<PieceRecord> restore(String id, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final current = await findById(id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该记录已不存在');
      }
      if (!current.isDeleted) {
        throw const ValidationFailure('该记录未被删除，无需恢复');
      }
      if (!TrashPolicy.canRestore(current.deletedAt)) {
        throw const TrashExpiredFailure();
      }
      await MonthLockGuard.assertEditable(executor, [Dates.ymOfYmd(current.date)]);
      await executor.update(
        Tables.pieceRecords,
        {'deleted_at': null, 'updated_at': AppClock.nowMillis()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return current.copyWith(clearDeletedAt: true, updatedAt: AppClock.nowMillis());
    });
  }

  Future<PieceRecord?> findById(String id, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.pieceRecords,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PieceRecord.fromMap(rows.first);
  }

  Future<List<PieceRecord>> listByDate(
    String date, {
    String? workerId,
    DatabaseExecutor? ex,
  }) {
    return listRange(
      DateRange.of(date, date),
      workerId: workerId,
      ex: ex,
    );
  }

  Future<List<PieceRecord>> listRange(
    DateRange range, {
    String? workerId,
    String? toyId,
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
    if (toyId != null) {
      where.add('toy_id = ?');
      args.add(toyId);
    }
    final rows = await executor.query(
      Tables.pieceRecords,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(PieceRecord.fromMap).toList(growable: false);
  }

  /// 回收站列表。默认隐藏超过 30 天的记录（不物理删除）。
  Future<List<PieceRecord>> listTrash({
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
      Tables.pieceRecords,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'deleted_at DESC',
    );
    return rows.map(PieceRecord.fromMap).toList(growable: false);
  }

  Future<int> countInRange(DateRange range, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final result = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.pieceRecords} '
      'WHERE date >= ? AND date <= ? AND deleted_at IS NULL',
      [range.start, range.end],
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
