import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/app_database.dart';
import '../models/settlement.dart';

/// 结算聚合仓储。
///
/// 采用「SQL 分组 + Dart 合并」两步：
/// * 计件按 (worker_id, toy_id, process_snapshot, unit_price_snapshot) 分组，
///   保证中途调价必然拆行，绝不出现平均单价；
/// * 调整项按类型汇总，与计件结果在内存中合并，
///   这样「只有调整项、没有计件」的工人也能进入结算清单。
class SettlementRepository {
  SettlementRepository(this._db);

  final AppDatabase _db;

  Future<SettlementResult> settle(
    DateRange range, {
    String? workerId,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;

    final whereWorker = workerId == null ? '' : ' AND worker_id = ?';
    final pieceArgs = <Object?>[range.start, range.end, ?workerId];
    final adjustArgs = <Object?>[range.start, range.end, ?workerId];

    final pieceRows = await executor.rawQuery(
      '''
      SELECT worker_id,
             toy_id,
             MAX(toy_name_snapshot) AS toy_name,
             process_snapshot,
             unit_price_snapshot,
             SUM(quantity) AS qty,
             SUM(subtotal_cents) AS total_cents
        FROM ${Tables.pieceRecords}
       WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker
       GROUP BY worker_id, toy_id, process_snapshot, unit_price_snapshot
       ORDER BY toy_name ASC, process_snapshot ASC, unit_price_snapshot ASC
      ''',
      pieceArgs,
    );

    final adjustRows = await executor.rawQuery(
      '''
      SELECT worker_id, type, SUM(amount_cents) AS total_cents, COUNT(*) AS cnt
        FROM ${Tables.adjustments}
       WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker
       GROUP BY worker_id, type
      ''',
      adjustArgs,
    );

    final recordCountRows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.pieceRecords} '
      'WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker',
      pieceArgs,
    );
    final recordCount = (recordCountRows.first['c'] as int?) ?? 0;

    // 收集涉及到的工人 id
    final workerIds = <String>{
      ...pieceRows.map((row) => row['worker_id']! as String),
      ...adjustRows.map((row) => row['worker_id']! as String),
    };
    if (workerIds.isEmpty) {
      return SettlementResult(range: range, workers: const [], recordCount: 0);
    }

    final workerMap = <String, ({String name, String code, bool archived})>{};
    final placeholders = List.filled(workerIds.length, '?').join(',');
    final workerRows = await executor.query(
      Tables.workers,
      columns: ['id', 'code', 'name', 'is_archived'],
      where: 'id IN ($placeholders)',
      whereArgs: workerIds.toList(growable: false),
    );
    for (final row in workerRows) {
      workerMap[row['id']! as String] = (
        name: row['name']! as String,
        code: (row['code'] as String?) ?? '',
        archived: (row['is_archived'] as int? ?? 0) == 1,
      );
    }

    // 计件分组：workerId -> List<PieceGroup>
    final groupsByWorker = <String, List<PieceGroup>>{};
    final pieceCentsByWorker = <String, int>{};
    for (final row in pieceRows) {
      final id = row['worker_id']! as String;
      final subtotal = (row['total_cents'] as int?) ?? 0;
      groupsByWorker.putIfAbsent(id, () => []).add(
            PieceGroup(
              toyId: row['toy_id']! as String,
              toyName: (row['toy_name'] as String?) ?? '',
              process: (row['process_snapshot'] as String?) ?? Defaults.defaultProcess,
              unitPriceTenThousandth: (row['unit_price_snapshot'] as int?) ?? 0,
              quantity: (row['qty'] as int?) ?? 0,
              subtotalCents: subtotal,
            ),
          );
      pieceCentsByWorker[id] = (pieceCentsByWorker[id] ?? 0) + subtotal;
    }

    // 调整项汇总：workerId -> {type: cents}
    final adjustByWorker = <String, Map<AdjustmentType, int>>{};
    for (final row in adjustRows) {
      final id = row['worker_id']! as String;
      final type = AdjustmentType.tryFromCode(row['type']! as String);
      if (type == null) continue;
      final map = adjustByWorker.putIfAbsent(id, () => <AdjustmentType, int>{});
      map[type] = (map[type] ?? 0) + ((row['total_cents'] as int?) ?? 0);
    }

    final settlements = <WorkerSettlement>[];
    for (final id in workerIds) {
      final info = workerMap[id];
      final groups = List<PieceGroup>.unmodifiable(
        groupsByWorker[id] ?? const <PieceGroup>[],
      );
      final adjustments = adjustByWorker[id] ?? const <AdjustmentType, int>{};
      final pieceCents = pieceCentsByWorker[id] ?? 0;
      if (groups.isEmpty && adjustments.isEmpty) continue;
      settlements.add(
        WorkerSettlement(
          workerId: id,
          workerCode: info?.code ?? '',
          // 工人档案不会物理删除；万一缺失（异常数据）用计件快照兜底
          workerName: info?.name ?? _fallbackName(pieceRows, adjustRows, id),
          isArchived: info?.archived ?? false,
          groups: groups,
          adjustmentTotals: Map<AdjustmentType, int>.unmodifiable(adjustments),
          pieceCents: pieceCents,
        ),
      );
    }

    settlements.sort((a, b) {
      final byAmount = b.netCents.compareTo(a.netCents);
      if (byAmount != 0) return byAmount;
      return a.workerName.compareTo(b.workerName);
    });

    return SettlementResult(
      range: range,
      workers: List<WorkerSettlement>.unmodifiable(settlements),
      recordCount: recordCount,
    );
  }

  String _fallbackName(
    List<Map<String, Object?>> pieceRows,
    List<Map<String, Object?>> adjustRows,
    String workerId,
  ) {
    for (final row in pieceRows) {
      if (row['worker_id'] == workerId) return '（已删除工人）';
    }
    return '（未知工人）';
  }

  /// 概览页：当日笔数 / 出勤人数 / 计件总额。
  Future<DayOverview> overview(String date, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;

    final piece = await executor.rawQuery(
      'SELECT COUNT(*) AS c, COUNT(DISTINCT worker_id) AS w, '
      'COALESCE(SUM(subtotal_cents), 0) AS s '
      'FROM ${Tables.pieceRecords} WHERE date = ? AND deleted_at IS NULL',
      [date],
    );
    final adjust = await executor.rawQuery(
      'SELECT COUNT(*) AS c, COUNT(DISTINCT worker_id) AS w '
      'FROM ${Tables.adjustments} WHERE date = ? AND deleted_at IS NULL',
      [date],
    );

    final pieceRow = piece.first;
    final adjustRow = adjust.first;
    final recordCount = (pieceRow['c'] as int?) ?? 0;
    final adjustmentCount = (adjustRow['c'] as int?) ?? 0;

    // 出勤人数 = 当天有计件或有调整项的去重人数
    final workerIds = <String>{};
    final pieceWorkers = await executor.rawQuery(
      'SELECT DISTINCT worker_id FROM ${Tables.pieceRecords} '
      'WHERE date = ? AND deleted_at IS NULL',
      [date],
    );
    final adjustWorkers = await executor.rawQuery(
      'SELECT DISTINCT worker_id FROM ${Tables.adjustments} '
      'WHERE date = ? AND deleted_at IS NULL',
      [date],
    );
    for (final row in pieceWorkers) {
      workerIds.add(row['worker_id']! as String);
    }
    for (final row in adjustWorkers) {
      workerIds.add(row['worker_id']! as String);
    }

    return DayOverview(
      date: date,
      recordCount: recordCount,
      workerCount: workerIds.length,
      pieceCents: (pieceRow['s'] as int?) ?? 0,
      adjustmentCount: adjustmentCount,
    );
  }

}
