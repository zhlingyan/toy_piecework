import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';

/// 年度报表里的一行：某工人做某玩具某工序的年产量与年工资。
class AnnualLine {
  const AnnualLine({
    required this.toyId,
    required this.toyName,
    required this.process,
    required this.quantity,
    required this.cents,
    required this.lastDate,
  });

  final String toyId;
  final String toyName;
  final String process;
  final int quantity;
  final int cents;

  /// 该行最后一次出现的日期，便于判断是不是「老工序」。
  final String lastDate;
}

/// 某工人的年度汇总。
class AnnualWorker {
  const AnnualWorker({
    required this.workerId,
    required this.workerCode,
    required this.workerName,
    required this.isArchived,
    required this.quantity,
    required this.cents,
    required this.lines,
  });

  final String workerId;
  final String workerCode;
  final String workerName;
  final bool isArchived;
  final int quantity;
  final int cents;
  final List<AnnualLine> lines;

  int get lineCount => lines.length;
}

/// 年度报表：仅统计未删除的计件流水，不含调整项（调整项无产量含义）。
class AnnualReport {
  const AnnualReport({
    required this.year,
    required this.workers,
    required this.quantity,
    required this.cents,
  });

  final int year;
  final List<AnnualWorker> workers;
  final int quantity;
  final int cents;

  bool get isEmpty => workers.isEmpty;

  int get workerCount => workers.length;

  /// 年产量最高的工人（空报表返回 null）。
  AnnualWorker? get topWorker {
    if (workers.isEmpty) return null;
    var best = workers.first;
    for (final worker in workers) {
      if (worker.quantity > best.quantity) best = worker;
    }
    return best;
  }
}

/// 员工档案里的一天：当天产量、计件额与调整项净额。
class WorkerDaySummary {
  const WorkerDaySummary({
    required this.date,
    required this.quantity,
    required this.pieceCents,
    required this.recordCount,
    required this.adjustmentNetCents,
    required this.adjustmentCount,
  });

  final String date;
  final int quantity;
  final int pieceCents;
  final int recordCount;

  /// 当天调整项净额（补贴+计时-扣款-预支）。
  final int adjustmentNetCents;
  final int adjustmentCount;

  bool get isEmpty => recordCount == 0 && adjustmentCount == 0;
}

/// 员工档案聚合：累计数据 + 历史玩具 + 每日时间线。
class WorkerProfile {
  const WorkerProfile({
    required this.workerId,
    required this.totalQuantity,
    required this.totalCents,
    required this.firstDate,
    required this.lastDate,
    required this.toys,
    required this.days,
  });

  final String workerId;
  final int totalQuantity;
  final int totalCents;

  /// 首次/最近一次有计件的日期；无记录时为 null。
  final String? firstDate;
  final String? lastDate;

  /// 历史做过的玩具（按累计工资倒序）。
  final List<AnnualLine> toys;

  /// 每日时间线（按日期倒序，最多 [limit] 天）。
  final List<WorkerDaySummary> days;

  bool get isEmpty => totalQuantity == 0 && toys.isEmpty;
}

/// 报表聚合服务：年度报表与员工档案共用同一套 SQL，避免口径漂移。
class ReportService {
  ReportService(this._db);

  final AppDatabase _db;

  /// 年度报表。一次查出「工人 × 玩具 × 工序」，再在 Dart 里按工人归并。
  Future<AnnualReport> annual(int year, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final start = '$year-01-01';
    final end = '$year-12-31';

    final rows = await executor.rawQuery(
      '''
      SELECT r.worker_id,
             r.toy_id,
             MAX(r.toy_name_snapshot) AS toy_name,
             r.process_snapshot,
             SUM(r.quantity) AS qty,
             SUM(r.subtotal_cents) AS total_cents,
             MAX(r.date) AS last_date
        FROM ${Tables.pieceRecords} r
       WHERE r.date >= ? AND r.date <= ? AND r.deleted_at IS NULL
       GROUP BY r.worker_id, r.toy_id, r.process_snapshot
       ORDER BY r.worker_id ASC, total_cents DESC
      ''',
      [start, end],
    );

    if (rows.isEmpty) {
      return AnnualReport(
        year: year,
        workers: const [],
        quantity: 0,
        cents: 0,
      );
    }

    final workerIds = <String>{
      for (final row in rows) row['worker_id']! as String,
    };
    final info = await _workerInfo(executor, workerIds);

    final linesByWorker = <String, List<AnnualLine>>{};
    for (final row in rows) {
      final id = row['worker_id']! as String;
      linesByWorker.putIfAbsent(id, () => []).add(
            AnnualLine(
              toyId: row['toy_id']! as String,
              toyName: (row['toy_name'] as String?) ?? '',
              process: (row['process_snapshot'] as String?) ?? Defaults.defaultProcess,
              quantity: (row['qty'] as int?) ?? 0,
              cents: (row['total_cents'] as int?) ?? 0,
              lastDate: (row['last_date'] as String?) ?? '',
            ),
          );
    }

    final workers = <AnnualWorker>[];
    var totalQuantity = 0;
    var totalCents = 0;
    linesByWorker.forEach((id, lines) {
      final meta = info[id];
      final quantity = lines.fold(0, (sum, line) => sum + line.quantity);
      final cents = lines.fold(0, (sum, line) => sum + line.cents);
      totalQuantity += quantity;
      totalCents += cents;
      workers.add(
        AnnualWorker(
          workerId: id,
          workerCode: meta?.code ?? '',
          workerName: meta?.name ?? '（未知工人）',
          isArchived: meta?.archived ?? false,
          quantity: quantity,
          cents: cents,
          lines: List<AnnualLine>.unmodifiable(lines),
        ),
      );
    });

    workers.sort((a, b) {
      final byQuantity = b.quantity.compareTo(a.quantity);
      if (byQuantity != 0) return byQuantity;
      return a.workerName.compareTo(b.workerName);
    });

    return AnnualReport(
      year: year,
      workers: List<AnnualWorker>.unmodifiable(workers),
      quantity: totalQuantity,
      cents: totalCents,
    );
  }

  /// 员工档案：累计产量、历史玩具、每日时间线。
  Future<WorkerProfile> profile(
    String workerId, {
    int dayLimit = 60,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;

    final totals = await executor.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS qty, '
      'COALESCE(SUM(subtotal_cents), 0) AS cents, '
      'MIN(date) AS first_date, MAX(date) AS last_date '
      'FROM ${Tables.pieceRecords} '
      'WHERE worker_id = ? AND deleted_at IS NULL',
      [workerId],
    );
    final totalRow = totals.first;

    final toyRows = await executor.rawQuery(
      '''
      SELECT toy_id,
             MAX(toy_name_snapshot) AS toy_name,
             process_snapshot,
             SUM(quantity) AS qty,
             SUM(subtotal_cents) AS total_cents,
             MAX(date) AS last_date
        FROM ${Tables.pieceRecords}
       WHERE worker_id = ? AND deleted_at IS NULL
       GROUP BY toy_id, process_snapshot
       ORDER BY total_cents DESC
      ''',
      [workerId],
    );

    final days = await _timeline(executor, workerId, dayLimit);

    return WorkerProfile(
      workerId: workerId,
      totalQuantity: (totalRow['qty'] as int?) ?? 0,
      totalCents: (totalRow['cents'] as int?) ?? 0,
      firstDate: totalRow['first_date'] as String?,
      lastDate: totalRow['last_date'] as String?,
      toys: List<AnnualLine>.unmodifiable(
        toyRows.map(
          (row) => AnnualLine(
            toyId: row['toy_id']! as String,
            toyName: (row['toy_name'] as String?) ?? '',
            process: (row['process_snapshot'] as String?) ?? Defaults.defaultProcess,
            quantity: (row['qty'] as int?) ?? 0,
            cents: (row['total_cents'] as int?) ?? 0,
            lastDate: (row['last_date'] as String?) ?? '',
          ),
        ),
      ),
      days: days,
    );
  }

  /// 每日时间线：计件按日汇总，调整项按日汇总后合并，最近 N 天倒序。
  Future<List<WorkerDaySummary>> _timeline(
    DatabaseExecutor executor,
    String workerId,
    int dayLimit,
  ) async {
    final pieceRows = await executor.rawQuery(
      '''
      SELECT date,
             SUM(quantity) AS qty,
             SUM(subtotal_cents) AS total_cents,
             COUNT(*) AS cnt
        FROM ${Tables.pieceRecords}
       WHERE worker_id = ? AND deleted_at IS NULL
       GROUP BY date
       ORDER BY date DESC
       LIMIT ?
      ''',
      [workerId, dayLimit],
    );

    final adjustRows = await executor.rawQuery(
      '''
      SELECT date, type, COUNT(*) AS cnt, SUM(amount_cents) AS total_cents
        FROM ${Tables.adjustments}
       WHERE worker_id = ? AND deleted_at IS NULL
       GROUP BY date, type
      ''',
      [workerId],
    );

    final adjustByDate = <String, ({int net, int count})>{};
    for (final row in adjustRows) {
      final date = row['date']! as String;
      final type = AdjustmentType.tryFromCode(row['type']! as String);
      if (type == null) continue;
      final amount = (row['total_cents'] as int?) ?? 0;
      final count = (row['cnt'] as int?) ?? 0;
      final current = adjustByDate[date] ?? (net: 0, count: 0);
      adjustByDate[date] = (
        net: current.net + type.sign * amount,
        count: current.count + count,
      );
    }

    final byDate = <String, WorkerDaySummary>{};
    for (final row in pieceRows) {
      final date = row['date']! as String;
      final adjust = adjustByDate[date];
      byDate[date] = WorkerDaySummary(
        date: date,
        quantity: (row['qty'] as int?) ?? 0,
        pieceCents: (row['total_cents'] as int?) ?? 0,
        recordCount: (row['cnt'] as int?) ?? 0,
        adjustmentNetCents: adjust?.net ?? 0,
        adjustmentCount: adjust?.count ?? 0,
      );
    }

    // 只有调整项、没有计件的日期也要出现在时间线里
    adjustByDate.forEach((date, adjust) {
      if (byDate.containsKey(date)) return;
      byDate[date] = WorkerDaySummary(
        date: date,
        quantity: 0,
        pieceCents: 0,
        recordCount: 0,
        adjustmentNetCents: adjust.net,
        adjustmentCount: adjust.count,
      );
    });

    final result = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return List<WorkerDaySummary>.unmodifiable(
      result.take(dayLimit).toList(growable: false),
    );
  }

  Future<Map<String, ({String code, String name, bool archived})>> _workerInfo(
    DatabaseExecutor executor,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await executor.query(
      Tables.workers,
      columns: ['id', 'code', 'name', 'is_archived'],
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(growable: false),
    );
    return {
      for (final row in rows)
        row['id']! as String: (
          code: (row['code'] as String?) ?? '',
          name: (row['name'] as String?) ?? '',
          archived: (row['is_archived'] as int? ?? 0) == 1,
        ),
    };
  }
}
