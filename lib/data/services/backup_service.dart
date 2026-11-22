import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../db/app_database.dart';
import '../db/schema.dart';

/// 备份文件的统计信息（恢复前预览、备份列表展示共用）。
class BackupSummary {
  const BackupSummary({
    required this.format,
    required this.version,
    required this.exportedAt,
    required this.workerCount,
    required this.toyCount,
    required this.recordCount,
    required this.adjustmentCount,
    required this.lockedMonthCount,
    this.processCount = 0,
    required this.minDate,
    required this.maxDate,
  });

  final String format;
  final int version;
  final int exportedAt;
  final int workerCount;
  final int toyCount;
  final int recordCount;
  final int adjustmentCount;
  final int lockedMonthCount;

  /// 工序选项条数（v3 起才有；老备份为 0）。
  final int processCount;

  /// 流水日期跨度，用于恢复前让管理员确认「是不是这份账」。
  final String? minDate;
  final String? maxDate;

  String get exportedAtLabel {
    if (exportedAt <= 0) return '未知';
    final time = DateTime.fromMillisecondsSinceEpoch(exportedAt);
    return '${Dates.ymd(time)} ${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String get dateRangeLabel {
    if (minDate == null || maxDate == null) return '无流水';
    return minDate == maxDate ? minDate! : '$minDate ~ $maxDate';
  }
}

/// 校验通过的备份，可直接交给 [BackupService.restore]。
class BackupPreview {
  const BackupPreview({required this.summary, required this.payload});

  final BackupSummary summary;

  /// 规范化后的 data 段，键为表名。
  final Map<String, List<Map<String, Object?>>> payload;
}

class RestoreResult {
  const RestoreResult({
    required this.summary,
    required this.safetyBackupPath,
  });

  final BackupSummary summary;

  /// 覆盖前自动生成的当前账本快照路径，恢复错了还能退回去。
  final String safetyBackupPath;
}

/// 本地备份 / 恢复。
///
/// 恢复流程严格遵守：校验 → 预览 → 自动快照当前账本 → 事务内覆盖（失败整体回滚）。
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const List<String> _tableKeys = [
    Tables.workers,
    Tables.toys,
    Tables.pieceRecords,
    Tables.adjustments,
    Tables.lockedMonths,
    Tables.processPresets,
  ];

  /// 导出整本账。默认不含「删除已超 30 天」的流水，可在界面勾选包含。
  Future<Map<String, Object?>> buildPayload({
    bool includeExpiredDeleted = false,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final now = AppClock.nowMillis();

    final expiredFilter = includeExpiredDeleted
        ? ''
        : ' AND (deleted_at IS NULL OR deleted_at >= ${now - Limits.trashRetentionDays * 24 * 3600 * 1000})';

    final workers = await executor.query(Tables.workers, orderBy: 'code ASC');
    final toys = await executor.query(Tables.toys, orderBy: 'name ASC');
    final records = await executor.rawQuery(
      'SELECT * FROM ${Tables.pieceRecords} WHERE 1 = 1$expiredFilter '
      'ORDER BY date ASC, created_at ASC',
    );
    final adjustments = await executor.rawQuery(
      'SELECT * FROM ${Tables.adjustments} WHERE 1 = 1$expiredFilter '
      'ORDER BY date ASC, created_at ASC',
    );
    final locked = await executor.query(Tables.lockedMonths, orderBy: 'month ASC');
    final processes = await executor.query(
      Tables.processPresets,
      orderBy: 'is_builtin DESC, sort_order ASC, created_at ASC',
    );

    return {
      'format': Defaults.backupFormat,
      'version': Defaults.backupVersion,
      'exported_at': now,
      'counts': {
        Tables.workers: workers.length,
        Tables.toys: toys.length,
        Tables.pieceRecords: records.length,
        Tables.adjustments: adjustments.length,
        Tables.lockedMonths: locked.length,
        Tables.processPresets: processes.length,
      },
      'data': {
        Tables.workers: workers,
        Tables.toys: toys,
        Tables.pieceRecords: records,
        Tables.adjustments: adjustments,
        Tables.lockedMonths: locked,
        Tables.processPresets: processes,
      },
    };
  }

  Future<String> buildJson({
    bool includeExpiredDeleted = false,
    DatabaseExecutor? ex,
  }) async {
    final payload = await buildPayload(
      includeExpiredDeleted: includeExpiredDeleted,
      ex: ex,
    );
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 生成备份文件名：带版本号 + 时间戳，便于人工辨认。
  static String buildFileName({DateTime? now, String prefix = '玩具厂计件备份'}) {
    final time = now ?? AppClock.now();
    final stamp = '${time.year.toString().padLeft(4, '0')}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}-'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
    return '$prefix-v${Defaults.backupVersion}-$stamp.json';
  }

  /// 只读校验 + 预览，不触碰数据库。
  BackupPreview inspect(String jsonText) {
    final Map<String, Object?> root;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw const BackupFailure('备份文件格式不正确：根节点应为对象');
      }
      root = decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      throw const BackupFailure('备份文件已损坏，无法解析（不是合法的 JSON）');
    }

    final format = root['format'];
    if (format != Defaults.backupFormat) {
      throw const BackupFailure('这不是本应用的备份文件，已拒绝恢复');
    }
    final version = root['version'];
    if (version is! int) {
      throw const BackupFailure('备份文件缺少版本号，已拒绝恢复');
    }
    if (version > Defaults.backupVersion) {
      throw BackupFailure(
        '备份文件版本（v$version）高于当前应用（v${Defaults.backupVersion}），请先升级应用',
      );
    }

    final data = root['data'];
    if (data is! Map) {
      throw const BackupFailure('备份文件缺少数据段，已拒绝恢复');
    }

    final payload = <String, List<Map<String, Object?>>>{};
    for (final table in _tableKeys) {
      final raw = data[table];
      if (raw == null) {
        payload[table] = const [];
        continue;
      }
      if (raw is! List) {
        throw BackupFailure('备份文件数据结构异常：$table 不是列表');
      }
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < raw.length; i++) {
        final row = raw[i];
        if (row is! Map) {
          throw BackupFailure('备份文件数据结构异常：$table 第 ${i + 1} 条不是对象');
        }
        rows.add(_normalizeRow(table, row.map((k, v) => MapEntry(k.toString(), v)), i));
      }
      payload[table] = rows;
    }

    final summary = _summarize(
      root: root,
      version: version,
      payload: payload,
    );
    return BackupPreview(summary: summary, payload: payload);
  }

  Map<String, Object?> _normalizeRow(
    String table,
    Map<String, Object?> row,
    int index,
  ) {
    String requireString(String key, {bool allowEmpty = true}) {
      final value = row[key];
      if (value is String && (allowEmpty || value.isNotEmpty)) return value;
      if (value is num) return value.toString();
      throw BackupFailure('$table 第 ${index + 1} 条缺少字段 $key');
    }

    int requireInt(String key) {
      final value = row[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      throw BackupFailure('$table 第 ${index + 1} 条字段 $key 不是整数');
    }

    switch (table) {
      case Tables.workers:
        return {
          'id': requireString('id'),
          'code': row['code']?.toString() ?? '',
          'name': requireString('name'),
          'pinyin_initials': row['pinyin_initials']?.toString() ?? '',
          'is_archived': (row['is_archived'] as num?)?.toInt() ?? 0,
          'created_at': requireInt('created_at'),
          'updated_at': requireInt('updated_at'),
        };
      case Tables.toys:
        final price = row['unit_price_ten_thousandth'] ?? row['unit_price'];
        if (price == null) {
          throw BackupFailure('toys 第 ${index + 1} 条缺少单价字段');
        }
        int priceValue;
        if (price is int) {
          priceValue = price;
        } else if (price is num) {
          priceValue = (price * 10000).round();
        } else {
          final parsed = int.tryParse(price.toString());
          if (parsed == null) {
            throw BackupFailure('toys 第 ${index + 1} 条单价格式错误');
          }
          priceValue = parsed;
        }
        return {
          'id': requireString('id'),
          'name': requireString('name'),
          'process': (row['process'] as String?)?.trim().isNotEmpty == true
              ? row['process'] as String
              : Defaults.defaultProcess,
          'unit_price_ten_thousandth': priceValue,
          'overtime_price_ten_thousandth':
              (row['overtime_price_ten_thousandth'] as num?)?.toInt() ?? 0,
          'pinyin_initials': row['pinyin_initials']?.toString() ?? '',
          'is_archived': (row['is_archived'] as num?)?.toInt() ?? 0,
          'created_at': requireInt('created_at'),
          'updated_at': requireInt('updated_at'),
        };
      case Tables.pieceRecords:
        final date = requireString('date');
        if (!Dates.isValidYmd(date)) {
          throw BackupFailure('piece_records 第 ${index + 1} 条日期格式错误：$date');
        }
        final quantity = requireInt('quantity');
        if (quantity <= 0) {
          throw BackupFailure('piece_records 第 ${index + 1} 条数量必须大于 0');
        }
        return {
          'id': requireString('id'),
          'date': date,
          'worker_id': requireString('worker_id'),
          'toy_id': requireString('toy_id'),
          'worker_name_snapshot': requireString('worker_name_snapshot'),
          'toy_name_snapshot': requireString('toy_name_snapshot'),
          'process_snapshot': (row['process_snapshot'] as String?)?.trim().isNotEmpty == true
              ? row['process_snapshot'] as String
              : Defaults.defaultProcess,
          'unit_price_snapshot': requireInt('unit_price_snapshot'),
          'quantity': quantity,
          'subtotal_cents': requireInt('subtotal_cents'),
          // v1 备份没有这几个字段，一律按「非加班、时间未知」补齐，
          // 金额不受影响（subtotal_cents 原样保留）。
          'minute_of_day': (row['minute_of_day'] as num?)?.toInt() ?? 0,
          'overtime': (row['overtime'] as num?)?.toInt() ?? 0,
          'overtime_price_snapshot':
              (row['overtime_price_snapshot'] as num?)?.toInt() ?? 0,
          'overtime_multiplier':
              (row['overtime_multiplier'] as num?)?.toInt() ?? 1000,
          'remark': row['remark']?.toString() ?? '',
          'deleted_at': (row['deleted_at'] as num?)?.toInt(),
          'created_at': requireInt('created_at'),
          'updated_at': requireInt('updated_at'),
        };
      case Tables.adjustments:
        final date = requireString('date');
        if (!Dates.isValidYmd(date)) {
          throw BackupFailure('adjustments 第 ${index + 1} 条日期格式错误：$date');
        }
        final type = requireString('type');
        if (AdjustmentType.tryFromCode(type) == null) {
          throw BackupFailure('adjustments 第 ${index + 1} 条类型未知：$type');
        }
        var amount = requireInt('amount_cents');
        if (amount <= 0) {
          throw BackupFailure('adjustments 第 ${index + 1} 条金额必须大于 0');
        }
        // v1/v2 备份没有工时字段，缺失即按「直接填金额」处理
        final workMinutes = (row['work_minutes'] as num?)?.toInt() ?? 0;
        final hourlyRate = (row['hourly_rate_cents'] as num?)?.toInt() ?? 0;
        if (workMinutes < 0 || hourlyRate < 0) {
          throw BackupFailure('adjustments 第 ${index + 1} 条工时/时薪为负数');
        }
        if (workMinutes > 0 && hourlyRate > 0) {
          // 以工时 × 时薪为准重算，避免备份被手工改过导致两处对不上
          final derived = Money.hourlyCents(
            minutes: workMinutes,
            rateCentsPerHour: hourlyRate,
          );
          if (derived > 0) amount = derived;
        }
        return {
          'id': requireString('id'),
          'date': date,
          'worker_id': requireString('worker_id'),
          'worker_name_snapshot': requireString('worker_name_snapshot'),
          'type': type,
          'amount_cents': amount,
          'work_minutes': workMinutes,
          'hourly_rate_cents': hourlyRate,
          'minute_of_day': (row['minute_of_day'] as num?)?.toInt() ?? 0,
          'remark': requireString('remark', allowEmpty: false),
          'deleted_at': (row['deleted_at'] as num?)?.toInt(),
          'created_at': requireInt('created_at'),
          'updated_at': requireInt('updated_at'),
        };
      case Tables.processPresets:
        final name = requireString('name', allowEmpty: false).trim();
        if (name.isEmpty) {
          throw BackupFailure('process_presets 第 ${index + 1} 条工序名为空');
        }
        return {
          'name': name,
          'is_builtin': ((row['is_builtin'] as num?)?.toInt() ?? 0) == 0 ? 0 : 1,
          'sort_order': (row['sort_order'] as num?)?.toInt() ?? 0,
          'created_at': (row['created_at'] as num?)?.toInt() ?? 0,
        };
      case Tables.lockedMonths:
        final month = requireString('month');
        if (!Dates.isValidYm(month)) {
          throw BackupFailure('locked_months 第 ${index + 1} 条月份格式错误：$month');
        }
        return {
          'month': month,
          'is_locked': (row['is_locked'] as num?)?.toInt() ?? 1,
          'locked_at': (row['locked_at'] as num?)?.toInt(),
          'unlocked_at': (row['unlocked_at'] as num?)?.toInt(),
        };
      default:
        return row;
    }
  }

  BackupSummary _summarize({
    required Map<String, Object?> root,
    required int version,
    required Map<String, List<Map<String, Object?>>> payload,
  }) {
    final records = payload[Tables.pieceRecords] ?? const [];
    String? minDate;
    String? maxDate;
    for (final row in records) {
      final date = row['date'] as String;
      if (minDate == null || date.compareTo(minDate) < 0) minDate = date;
      if (maxDate == null || date.compareTo(maxDate) > 0) maxDate = date;
    }
    return BackupSummary(
      format: root['format']! as String,
      version: version,
      exportedAt: (root['exported_at'] as num?)?.toInt() ?? 0,
      workerCount: payload[Tables.workers]?.length ?? 0,
      toyCount: payload[Tables.toys]?.length ?? 0,
      recordCount: records.length,
      adjustmentCount: payload[Tables.adjustments]?.length ?? 0,
      processCount: payload[Tables.processPresets]?.length ?? 0,
      lockedMonthCount: payload[Tables.lockedMonths]?.length ?? 0,
      minDate: minDate,
      maxDate: maxDate,
    );
  }

  /// 覆盖恢复。
  ///
  /// [persistSafetyBackup] 由平台层实现（把当前账本 JSON 写成本地文件），
  /// 返回文件路径。只有快照写成功后才会进入覆盖事务。
  Future<RestoreResult> restore(
    BackupPreview preview, {
    required Future<String> Function(String json) persistSafetyBackup,
    DatabaseExecutor? ex,
  }) async {
    final currentJson = await buildJson(includeExpiredDeleted: true, ex: ex);
    final safetyPath = await persistSafetyBackup(currentJson);

    Future<void> writeAll(DatabaseExecutor executor) async {
      for (final statement in Schema.clearStatements) {
        await executor.rawDelete(statement);
      }
      for (final table in _tableKeys) {
        final rows = preview.payload[table] ?? const [];
        for (final row in rows) {
          await executor.insert(table, row);
        }
      }
      // 老备份（v2 及以前）没有工序表，恢复后列表会空掉，
      // 这里无条件补种预置项——`INSERT OR IGNORE` 对已有数据无害。
      for (final statement in Schema.seedProcessStatements) {
        await executor.execute(statement);
      }
    }

    if (ex != null) {
      await writeAll(ex);
    } else {
      await _db.transaction((txn) async {
        await writeAll(txn);
      });
    }

    return RestoreResult(summary: preview.summary, safetyBackupPath: safetyPath);
  }
}
