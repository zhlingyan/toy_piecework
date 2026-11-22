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
             overtime,
             overtime_price_snapshot,
             MAX(overtime_multiplier) AS overtime_multiplier,
             SUM(quantity) AS qty,
             SUM(subtotal_cents) AS total_cents
        FROM ${Tables.pieceRecords}
       WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker
       GROUP BY worker_id, toy_id, process_snapshot, unit_price_snapshot,
                overtime, overtime_price_snapshot
       ORDER BY toy_name ASC, process_snapshot ASC, unit_price_snapshot ASC,
                overtime ASC
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

    // 逐笔结算：一笔算已结的条件是「自己标了 settled_at」**或**「所在月整月已标」。
    // 用 LEFT JOIN 一次算完，避免把几千条流水拉到内存里再逐条判断。
    final pieceSettledRows = await executor.rawQuery(
      '''
      SELECT p.worker_id,
             SUM(CASE WHEN p.settled_at IS NOT NULL OR m.month IS NOT NULL
                      THEN p.subtotal_cents ELSE 0 END) AS settled_cents,
             SUM(CASE WHEN p.settled_at IS NOT NULL OR m.month IS NOT NULL
                      THEN 1 ELSE 0 END) AS settled_cnt,
             COUNT(*) AS cnt
        FROM ${Tables.pieceRecords} p
        LEFT JOIN ${Tables.settlementMarks} m
          ON m.worker_id = p.worker_id
         AND m.month = substr(p.date, 1, 7)
         AND m.is_settled = 1
       WHERE p.date >= ? AND p.date <= ? AND p.deleted_at IS NULL
             ${workerId == null ? '' : 'AND p.worker_id = ?'}
       GROUP BY p.worker_id
      ''',
      pieceArgs,
    );
    final adjustSettledRows = await executor.rawQuery(
      '''
      SELECT a.worker_id, a.type,
             SUM(CASE WHEN a.settled_at IS NOT NULL OR m.month IS NOT NULL
                      THEN a.amount_cents ELSE 0 END) AS settled_cents,
             SUM(CASE WHEN a.settled_at IS NOT NULL OR m.month IS NOT NULL
                      THEN 1 ELSE 0 END) AS settled_cnt,
             COUNT(*) AS cnt
        FROM ${Tables.adjustments} a
        LEFT JOIN ${Tables.settlementMarks} m
          ON m.worker_id = a.worker_id
         AND m.month = substr(a.date, 1, 7)
         AND m.is_settled = 1
       WHERE a.date >= ? AND a.date <= ? AND a.deleted_at IS NULL
             ${workerId == null ? '' : 'AND a.worker_id = ?'}
       GROUP BY a.worker_id, a.type
      ''',
      adjustArgs,
    );

    final settledCentsByWorker = <String, int>{};
    final settledCountByWorker = <String, int>{};
    final entryCountByWorker = <String, int>{};

    void addSettled(String id, int cents, int settledCount, int totalCount) {
      settledCentsByWorker[id] = (settledCentsByWorker[id] ?? 0) + cents;
      settledCountByWorker[id] = (settledCountByWorker[id] ?? 0) + settledCount;
      entryCountByWorker[id] = (entryCountByWorker[id] ?? 0) + totalCount;
    }

    for (final row in pieceSettledRows) {
      addSettled(
        row['worker_id']! as String,
        (row['settled_cents'] as int?) ?? 0,
        (row['settled_cnt'] as int?) ?? 0,
        (row['cnt'] as int?) ?? 0,
      );
    }
    for (final row in adjustSettledRows) {
      final type = AdjustmentType.tryFromCode(row['type']! as String);
      if (type == null) continue;
      // 调整项金额恒为正、方向由类型决定，已结金额要带符号累加，
      // 否则「预支已结」会把已结总额越加越多。
      addSettled(
        row['worker_id']! as String,
        type.sign * ((row['settled_cents'] as int?) ?? 0),
        (row['settled_cnt'] as int?) ?? 0,
        (row['cnt'] as int?) ?? 0,
      );
    }

    // 「总笔数」与「已结笔数 X/Y」的分母必须同源：都取逐笔查询里的
    // COUNT(*)（计件 + 补贴/计时/扣款/预支）。之前单独 COUNT(piece_records)
    // 只算计件，才会出现「笔数 16」与「已结笔数 20/20」并列。
    final recordCount = entryCountByWorker.values.fold(
      0,
      (sum, count) => sum + count,
    );

    // 按月拆分的金额：结算状态按「人 + 月」记，金额也必须能按月对上，
    // 否则「已结算 / 未结算」只能靠估算，对账时必然扯皮。
    final pieceMonthRows = await executor.rawQuery(
      '''
      SELECT worker_id, substr(date, 1, 7) AS month,
             SUM(subtotal_cents) AS total_cents
        FROM ${Tables.pieceRecords}
       WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker
       GROUP BY worker_id, month
      ''',
      pieceArgs,
    );
    final adjustMonthRows = await executor.rawQuery(
      '''
      SELECT worker_id, substr(date, 1, 7) AS month, type,
             SUM(amount_cents) AS total_cents
        FROM ${Tables.adjustments}
       WHERE date >= ? AND date <= ? AND deleted_at IS NULL$whereWorker
       GROUP BY worker_id, month, type
      ''',
      adjustArgs,
    );

    final monthNetByWorker = <String, Map<String, int>>{};
    void addMonthNet(String workerId, String month, int cents) {
      final map = monthNetByWorker.putIfAbsent(workerId, () => <String, int>{});
      map[month] = (map[month] ?? 0) + cents;
    }

    for (final row in pieceMonthRows) {
      addMonthNet(
        row['worker_id']! as String,
        row['month']! as String,
        (row['total_cents'] as int?) ?? 0,
      );
    }
    for (final row in adjustMonthRows) {
      final type = AdjustmentType.tryFromCode(row['type']! as String);
      if (type == null) continue;
      addMonthNet(
        row['worker_id']! as String,
        row['month']! as String,
        type.sign * ((row['total_cents'] as int?) ?? 0),
      );
    }

    // 收集涉及到的工人 id
    final workerIds = <String>{
      ...pieceRows.map((row) => row['worker_id']! as String),
      ...adjustRows.map((row) => row['worker_id']! as String),
    };
    if (workerIds.isEmpty) {
      return SettlementResult(range: range, workers: const [], recordCount: 0);
    }

    final settledByWorker = await _settledMonths(
      executor,
      workerIds,
      range.months,
    );

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
              overtime: ((row['overtime'] as int?) ?? 0) != 0,
              overtimePriceTenThousandth:
                  (row['overtime_price_snapshot'] as int?) ?? 0,
              overtimeMultiplier: (row['overtime_multiplier'] as int?) ?? 1000,
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
          monthNetCents: Map<String, int>.unmodifiable(
            monthNetByWorker[id] ?? const <String, int>{},
          ),
          settledMonths: Set<String>.unmodifiable(
            settledByWorker[id] ?? const <String>{},
          ),
          settledCents: settledCentsByWorker[id] ?? 0,
          settledCount: settledCountByWorker[id] ?? 0,
          recordCount: entryCountByWorker[id] ?? 0,
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

  /// 取这批工人在区间内「已标记结算」的月份。
  Future<Map<String, Set<String>>> _settledMonths(
    DatabaseExecutor executor,
    Set<String> workerIds,
    List<String> months,
  ) async {
    if (workerIds.isEmpty || months.isEmpty) return const {};
    final workerList = workerIds.toList(growable: false);
    final rows = await executor.rawQuery(
      'SELECT worker_id, month FROM ${Tables.settlementMarks} '
      'WHERE is_settled = 1 '
      'AND worker_id IN (${List.filled(workerList.length, '?').join(',')}) '
      'AND month IN (${List.filled(months.length, '?').join(',')})',
      [...workerList, ...months],
    );
    final result = <String, Set<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['worker_id']! as String, () => <String>{})
          .add(row['month']! as String);
    }
    return result;
  }

  /// 概览页：当日笔数 / 出勤人数 / 计件总额 + 完整出勤名单。
  Future<DayOverview> overview(String date, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;

    final piece = await executor.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(subtotal_cents), 0) AS s '
      'FROM ${Tables.pieceRecords} WHERE date = ? AND deleted_at IS NULL',
      [date],
    );
    final adjust = await executor.rawQuery(
      'SELECT COUNT(*) AS c '
      'FROM ${Tables.adjustments} WHERE date = ? AND deleted_at IS NULL',
      [date],
    );

    final pieceRow = piece.first;
    final adjustRow = adjust.first;
    final recordCount = (pieceRow['c'] as int?) ?? 0;
    final adjustmentCount = (adjustRow['c'] as int?) ?? 0;
    final pieceCents = (pieceRow['s'] as int?) ?? 0;

    // 名单口径：全部在职工人 + 当日有账的已停用工人。
    // 后者并进来是为了「出勤 ≤ 总人数」恒成立，避免 3/0 这类反逻辑展示。
    final peopleRows = await executor.rawQuery(
      '''
      SELECT id, code, name, is_archived
        FROM ${Tables.workers}
       WHERE is_archived = 0
          OR id IN (SELECT worker_id FROM ${Tables.pieceRecords}
                     WHERE date = ? AND deleted_at IS NULL)
          OR id IN (SELECT worker_id FROM ${Tables.adjustments}
                     WHERE date = ? AND deleted_at IS NULL)
      ''',
      [date, date],
    );

    // 当日按人汇总的笔数与净额：计件 + 调整项（带方向符号）。
    final pieceByWorker = await executor.rawQuery(
      'SELECT worker_id, COUNT(*) AS c, '
      'COALESCE(SUM(subtotal_cents), 0) AS s '
      'FROM ${Tables.pieceRecords} '
      'WHERE date = ? AND deleted_at IS NULL GROUP BY worker_id',
      [date],
    );
    final adjustByWorker = await executor.rawQuery(
      'SELECT worker_id, type, COUNT(*) AS c, '
      'COALESCE(SUM(amount_cents), 0) AS s '
      'FROM ${Tables.adjustments} '
      'WHERE date = ? AND deleted_at IS NULL GROUP BY worker_id, type',
      [date],
    );

    final counts = <String, int>{};
    final netCents = <String, int>{};
    for (final row in pieceByWorker) {
      final id = row['worker_id']! as String;
      counts[id] = (counts[id] ?? 0) + ((row['c'] as int?) ?? 0);
      netCents[id] = (netCents[id] ?? 0) + ((row['s'] as int?) ?? 0);
    }
    for (final row in adjustByWorker) {
      final type = AdjustmentType.tryFromCode(row['type']! as String);
      if (type == null) continue;
      final id = row['worker_id']! as String;
      counts[id] = (counts[id] ?? 0) + ((row['c'] as int?) ?? 0);
      netCents[id] =
          (netCents[id] ?? 0) + type.sign * ((row['s'] as int?) ?? 0);
    }

    final people = <AttendancePerson>[];
    for (final row in peopleRows) {
      final id = row['id']! as String;
      final count = counts[id] ?? 0;
      people.add(
        AttendancePerson(
          workerId: id,
          name: row['name']! as String,
          code: (row['code'] as String?) ?? '',
          isArchived: (row['is_archived'] as int? ?? 0) == 1,
          present: count > 0,
          recordCount: count,
          netCents: netCents[id] ?? 0,
        ),
      );
    }
    // 已出勤在前、未出勤置后；组内按姓名，名单稳定好找。
    people.sort((a, b) {
      if (a.present != b.present) return a.present ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return DayOverview(
      date: date,
      recordCount: recordCount,
      workerCount: people.where((p) => p.present).length,
      pieceCents: pieceCents,
      adjustmentCount: adjustmentCount,
      totalWorkerCount: people.length,
      people: List<AttendancePerson>.unmodifiable(people),
    );
  }

}
