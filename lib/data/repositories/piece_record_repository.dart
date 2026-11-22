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
import '../models/settlement_event.dart';
import '../models/toy.dart';
import '../models/worker.dart';
import 'settlement_history_repository.dart';

/// 计件流水仓储。
///
/// 三条铁律：
/// 1. 任何写入前先过 [MonthLockGuard]（锁账不可改）；
/// 2. 姓名/玩具/工序/单价一律写快照，档案后续变动不回溯历史；
/// 3. 永不物理删除，只写 `deleted_at`。
class PieceRecordRepository {
  PieceRecordRepository(this._db, {SettlementHistoryRepository? history}) {
    _history = history;
  }

  final AppDatabase _db;

  /// 可选：传入后，录入即结算 / 编辑改结算状态也会追加历史（同事务）。
  /// 不传（如某些单元测试）则只写状态，不记历史，行为与升级前一致。
  late final SettlementHistoryRepository? _history;

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
    int? minuteOfDay,
    bool overtime = false,
    int? overtimePriceTenThousandth,
    int overtimeMultiplier = 1000,
    bool settled = false,
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

      // 加班单价由调用方（OvertimeRules）算好传进来，这里只做合法性校验：
      // 勾了加班却没有有效加班价，宁可报错也不静默按正常价入账。
      final overtimePrice = overtimePriceTenThousandth ?? 0;
      final isOvertime = overtime;
      if (isOvertime && overtimePrice <= 0) {
        throw const ValidationFailure('加班单价必须大于 0');
      }
      final pricingPrice = isOvertime ? overtimePrice : price;

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
          priceTenThousandth: pricingPrice,
        ),
        minuteOfDay: (minuteOfDay ?? AppClock.nowMinuteOfDay())
            .clamp(0, Dates.minutesPerDay - 1),
        overtime: isOvertime,
        overtimePriceSnapshot: isOvertime ? overtimePrice : 0,
        overtimeMultiplier: isOvertime ? overtimeMultiplier : 1000,
        remark: remark.trim(),
        deletedAt: null,
        settledAt: settled ? now : null,
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
      if (settled) {
        // 「录入时即结算」也是一次结算动作，同样追加历史（理由为空）。
        await _history?.append(
          workerId: worker.id,
          action: SettlementAction.settled,
          scope: SettlementEventScope.entry,
          months: [Dates.ymOfYmd(date)],
          entryLabel: '$date · 计件流水',
          occurredAt: now,
          ex: executor,
        );
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
    int? minuteOfDay,
    bool? overtime,
    int? overtimePriceTenThousandth,
    int? overtimeMultiplier,
    bool? settled,
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

      final newOvertime = overtime ?? current.overtime;
      final newOvertimePrice =
          overtimePriceTenThousandth ?? current.overtimePriceSnapshot;
      if (newOvertime && newOvertimePrice <= 0) {
        throw const ValidationFailure('加班单价必须大于 0');
      }
      final pricingPrice = newOvertime ? newOvertimePrice : newPrice;

      // 只改备注时金额原样保留，避免历史分位在反复保存中漂移。
      final sameQuantityAndPrice = newQuantity == current.quantity &&
          newPrice == current.unitPriceSnapshot &&
          newOvertime == current.overtime &&
          newOvertimePrice == current.overtimePriceSnapshot;

      final updated = current.copyWith(
        date: newDate,
        minuteOfDay: (minuteOfDay ?? current.minuteOfDay)
            .clamp(0, Dates.minutesPerDay - 1),
        toyId: toyId,
        toyNameSnapshot: toyNameSnapshot,
        processSnapshot: processSnapshot,
        quantity: newQuantity,
        unitPriceSnapshot: newPrice,
        overtime: newOvertime,
        overtimePriceSnapshot: newOvertime ? newOvertimePrice : 0,
        overtimeMultiplier: newOvertime
            ? (overtimeMultiplier ?? current.overtimeMultiplier)
            : 1000,
        remark: (remark ?? current.remark).trim(),
        settledAt: settled == null
            ? current.settledAt
            : (settled ? (current.settledAt ?? AppClock.nowMillis()) : null),
        clearSettledAt: settled == false,
        subtotalCents: sameQuantityAndPrice
            ? current.subtotalCents
            : Money.subtotalCents(
                quantity: newQuantity,
                priceTenThousandth: pricingPrice,
              ),
        updatedAt: AppClock.nowMillis(),
      );

      await executor.update(
        Tables.pieceRecords,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      final wasSettled = current.settledAt != null;
      if (settled != null && settled != wasSettled) {
        await _history?.append(
          workerId: current.workerId,
          action: settled ? SettlementAction.settled : SettlementAction.unsettled,
          scope: SettlementEventScope.entry,
          months: [Dates.ymOfYmd(newDate)],
          entryLabel: '$newDate · 计件流水',
          occurredAt: updated.updatedAt,
          ex: executor,
        );
      }
      return updated;
    });
  }

  /// 单笔标记 / 取消结算。
  ///
  /// **不经过锁账校验**：锁账防的是"改账"，结算是记录"钱发没发"，
  /// 两者刻意解耦——发完钱锁了账，事后补个已结算标记不该被拦住。
  Future<void> setSettled(
    String id, {
    required bool settled,
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      final current = await findById(id, ex: executor);
      if (current == null) {
        throw const ValidationFailure('该记录已不存在');
      }
      if (current.isDeleted) {
        throw const ValidationFailure('已删除的记录不能标记结算，请先从回收站恢复');
      }
      final now = AppClock.nowMillis();
      await executor.update(
        Tables.pieceRecords,
        {
          'settled_at': settled ? now : null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final wasSettled = current.settledAt != null;
      if (settled != wasSettled) {
        await _history?.append(
          workerId: current.workerId,
          action: settled ? SettlementAction.settled : SettlementAction.unsettled,
          scope: SettlementEventScope.entry,
          months: [Dates.ymOfYmd(current.date)],
          entryLabel: '${current.date} · 计件流水',
          occurredAt: now,
          ex: executor,
        );
      }
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
      orderBy: 'date DESC, minute_of_day DESC, created_at DESC',
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
