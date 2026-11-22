import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../db/app_database.dart';

/// 旧账预览（导入前给管理员确认）。
class LegacyPreview {
  const LegacyPreview({
    required this.recordCount,
    required this.workerCount,
    required this.toyCount,
    required this.minDate,
    required this.maxDate,
    required this.willImport,
    required this.skippedExisting,
    required this.skippedLocked,
    required this.skippedInvalid,
    required this.warnings,
  });

  final int recordCount;
  final int workerCount;
  final int toyCount;
  final String? minDate;
  final String? maxDate;

  /// 重复导入时该值为 0，即「按原 ID 幂等去重」。
  final int willImport;
  final int skippedExisting;
  final int skippedLocked;
  final int skippedInvalid;
  final List<String> warnings;

  String get rangeLabel {
    if (minDate == null || maxDate == null) return '无有效流水';
    return minDate == maxDate ? minDate! : '$minDate ~ $maxDate';
  }
}

class LegacyImportResult {
  const LegacyImportResult({
    required this.inserted,
    required this.skippedExisting,
    required this.skippedLocked,
    required this.createdWorkers,
    required this.createdToys,
    required this.preview,
  });

  final int inserted;
  final int skippedExisting;
  final int skippedLocked;
  final int createdWorkers;
  final int createdToys;
  final LegacyPreview preview;
}

/// 微信小程序旧账导入。
///
/// 容错优先：字段名兼容驼峰/下划线/多种历史写法，金额同时接受「元」与「万分之一元」。
/// 幂等：按原 id 去重，重复导入新增 0 笔；缺失档案自动补建为**归档**状态，
/// 工序缺失默认「整件」。
class LegacyImportService {
  LegacyImportService(this._db);

  final AppDatabase _db;

  Future<LegacyPreview> inspect(String jsonText, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final data = _parse(jsonText);
    final existingIds = await _existingRecordIds(executor);
    final lockedMonths = await _lockedMonths(executor);
    return _buildPreview(data, existingIds, lockedMonths);
  }

  Future<LegacyImportResult> import(
    String jsonText, {
    DatabaseExecutor? ex,
  }) async {
    final data = _parse(jsonText);

    Future<LegacyImportResult> run(DatabaseExecutor executor) async {
      final existingIds = await _existingRecordIds(executor);
      final lockedMonths = await _lockedMonths(executor);
      final preview = _buildPreview(data, existingIds, lockedMonths);

      final now = AppClock.nowMillis();
      var createdWorkers = 0;
      var createdToys = 0;

      // 1. 补建工人档案（归档状态，避免污染录入列表）
      final existingWorkers = await executor.query(
        Tables.workers,
        columns: ['id'],
      );
      final workerIds = existingWorkers.map((row) => row['id']! as String).toSet();
      for (final worker in data.workers) {
        if (workerIds.contains(worker.id)) continue;
        await executor.insert(
          Tables.workers,
          {
            'id': worker.id,
            'code': worker.code,
            'name': worker.name,
            'pinyin_initials': worker.pinyinInitials,
            'is_archived': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        workerIds.add(worker.id);
        createdWorkers++;
      }

      // 2. 补建玩具档案（归档状态）
      final existingToys = await executor.query(Tables.toys, columns: ['id']);
      final toyIds = existingToys.map((row) => row['id']! as String).toSet();
      for (final toy in data.toys) {
        if (toyIds.contains(toy.id)) continue;
        await executor.insert(
          Tables.toys,
          {
            'id': toy.id,
            'name': toy.name,
            'process': toy.process,
            'unit_price_ten_thousandth': toy.unitPriceTenThousandth,
            'pinyin_initials': toy.pinyinInitials,
            'is_archived': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        toyIds.add(toy.id);
        createdToys++;
      }

      // 3. 写入流水：保留原 id / 单价 / 小计，已存在的跳过
      var inserted = 0;
      var skippedExisting = 0;
      var skippedLocked = 0;
      for (final record in data.records) {
        if (existingIds.contains(record.id)) {
          skippedExisting++;
          continue;
        }
        if (lockedMonths.contains(Dates.ymOfYmd(record.date))) {
          skippedLocked++;
          continue;
        }
        final rowId = await executor.insert(
          Tables.pieceRecords,
          {
            'id': record.id,
            'date': record.date,
            'worker_id': record.workerId,
            'toy_id': record.toyId,
            'worker_name_snapshot': record.workerName,
            'toy_name_snapshot': record.toyName,
            'process_snapshot': record.process,
            'unit_price_snapshot': record.unitPriceTenThousandth,
            'quantity': record.quantity,
            'subtotal_cents': record.subtotalCents,
            'remark': record.remark,
            'deleted_at': null,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (rowId == 0) {
          skippedExisting++;
        } else {
          inserted++;
        }
        existingIds.add(record.id);
      }

      return LegacyImportResult(
        inserted: inserted,
        skippedExisting: skippedExisting,
        skippedLocked: skippedLocked,
        createdWorkers: createdWorkers,
        createdToys: createdToys,
        preview: preview,
      );
    }

    if (ex != null) return run(ex);
    return _db.transaction(run);
  }

  Future<Set<String>> _existingRecordIds(DatabaseExecutor executor) async {
    final rows = await executor.query(Tables.pieceRecords, columns: ['id']);
    return rows.map((row) => row['id']! as String).toSet();
  }

  Future<Set<String>> _lockedMonths(DatabaseExecutor executor) async {
    final rows = await executor.query(
      Tables.lockedMonths,
      columns: ['month'],
      where: 'is_locked = 1',
    );
    return rows.map((row) => row['month']! as String).toSet();
  }

  LegacyPreview _buildPreview(
    _LegacyData data,
    Set<String> existingIds,
    Set<String> lockedMonths,
  ) {
    var willImport = 0;
    var skippedExisting = 0;
    var skippedLocked = 0;
    String? minDate;
    String? maxDate;
    for (final record in data.records) {
      if (minDate == null || record.date.compareTo(minDate) < 0) {
        minDate = record.date;
      }
      if (maxDate == null || record.date.compareTo(maxDate) > 0) {
        maxDate = record.date;
      }
      if (existingIds.contains(record.id)) {
        skippedExisting++;
      } else if (lockedMonths.contains(Dates.ymOfYmd(record.date))) {
        skippedLocked++;
      } else {
        willImport++;
      }
    }
    return LegacyPreview(
      recordCount: data.records.length,
      workerCount: data.workers.length,
      toyCount: data.toys.length,
      minDate: minDate,
      maxDate: maxDate,
      willImport: willImport,
      skippedExisting: skippedExisting,
      skippedLocked: skippedLocked,
      skippedInvalid: data.invalidCount,
      warnings: List.unmodifiable(data.warnings),
    );
  }

  // ---------------------------- 解析 ----------------------------

  _LegacyData _parse(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const LegacyImportFailure('旧账文件已损坏，无法解析（不是合法的 JSON）');
    }

    List<dynamic>? rawRecords;
    List<dynamic>? rawWorkers;
    List<dynamic>? rawToys;

    void readFromMap(Map<dynamic, dynamic> map) {
      rawRecords ??= _firstList(map, const [
        'piece_records',
        'pieceRecords',
        'records',
        'pieces',
        'items',
        'list',
      ]);
      rawWorkers ??= _firstList(map, const [
        'workers',
        'worker_list',
        'workerList',
        'staff',
      ]);
      rawToys ??= _firstList(map, const [
        'toys',
        'toy_list',
        'toyList',
        'products',
        'goods',
      ]);
    }

    if (decoded is List) {
      rawRecords = decoded;
    } else if (decoded is Map) {
      readFromMap(decoded);
      final nested = decoded['data'];
      if (nested is Map) readFromMap(nested);
      final resultList = decoded['result'];
      if (resultList is Map) readFromMap(resultList);
    } else {
      throw const LegacyImportFailure('旧账文件结构无法识别，请确认导出的是小程序账本 JSON');
    }

    if (rawRecords == null || rawRecords!.isEmpty) {
      throw const LegacyImportFailure('旧账文件里没有找到任何流水记录');
    }

    final warnings = <String>[];
    var invalid = 0;

    final workers = <String, _LegacyWorker>{};
    // 文件里显式声明的工人优先
    for (final item in rawWorkers ?? const []) {
      if (item is! Map) continue;
      final name = _text(item, const ['name', 'workerName', 'worker_name']);
      if (name == null || name.isEmpty) continue;
      final id = _text(item, const ['id', '_id', 'workerId', 'worker_id']) ??
          _derivedId('worker', name);
      workers[id] = _LegacyWorker(
        id: id,
        name: name,
        code: _text(item, const ['code', 'no', 'number']) ?? '',
        pinyinInitials:
            (_text(item, const ['pinyin_initials', 'pinyinInitials', 'initials']) ?? '')
                .toUpperCase(),
      );
    }

    final toys = <String, _LegacyToy>{};
    for (final item in rawToys ?? const []) {
      if (item is! Map) continue;
      final name = _text(item, const ['name', 'toyName', 'toy_name', 'productName']);
      if (name == null || name.isEmpty) continue;
      final id = _text(item, const ['id', '_id', 'toyId', 'toy_id']) ??
          _derivedId('toy', name);
      final process =
          _text(item, const ['process', 'procedure', 'step']) ?? Defaults.defaultProcess;
      final price = _priceTenThousandth(item, const [
            'unit_price_ten_thousandth',
            'unitPriceTenThousandth',
            'unit_price',
            'unitPrice',
            'price',
          ]) ??
          0;
      toys[id] = _LegacyToy(
        id: id,
        name: name,
        process: process.isEmpty ? Defaults.defaultProcess : process,
        unitPriceTenThousandth: price,
        pinyinInitials:
            (_text(item, const ['pinyin_initials', 'pinyinInitials', 'initials']) ?? '')
                .toUpperCase(),
      );
    }

    final records = <_LegacyRecord>[];
    final seenIds = <String>{};
    for (var index = 0; index < rawRecords!.length; index++) {
      final item = rawRecords![index];
      if (item is! Map) {
        invalid++;
        continue;
      }
      final date = _date(item, const ['date', 'workDate', 'work_date', 'day', 'createdAt']);
      final quantity = _int(item, const ['quantity', 'qty', 'count', 'num', 'pieces']);
      if (date == null || quantity == null || quantity <= 0) {
        invalid++;
        continue;
      }

      final workerName =
          _text(item, const ['workerName', 'worker_name', 'worker']) ?? '未知工人';
      final workerId = _text(item, const ['workerId', 'worker_id']) ??
          _derivedId('worker', workerName);
      final toyName =
          _text(item, const ['toyName', 'toy_name', 'productName', 'product']) ?? '未知玩具';
      final toyId =
          _text(item, const ['toyId', 'toy_id', 'productId']) ?? _derivedId('toy', toyName);
      var process = _text(item, const ['process', 'processName', 'procedure']) ?? '';
      if (process.trim().isEmpty) process = Defaults.defaultProcess;

      final explicitPrice = _priceTenThousandth(item, const [
        'unit_price_ten_thousandth',
        'unitPriceTenThousandth',
      ]);
      final yuanPrice = _priceTenThousandth(item, const ['unitPrice', 'unit_price', 'price']);
      final subtotalCents = _cents(item, const [
        'subtotal_cents',
        'subtotalCents',
        'subtotal',
        'total',
        'amount',
      ]);

      int price;
      if (explicitPrice != null) {
        price = explicitPrice;
      } else if (yuanPrice != null) {
        price = yuanPrice;
      } else if (subtotalCents != null && quantity > 0) {
        // 只有小计：反推单价，保证「小计不变」优先于「单价还原」
        price = ((subtotalCents * 100) / quantity).round();
      } else {
        price = 0;
        warnings.add('第 ${index + 1} 条记录缺少单价与小计，已按 0 元导入');
      }

      final cents = subtotalCents ??
          Money.subtotalCents(quantity: quantity, priceTenThousandth: price);

      final rawId = _text(item, const ['id', '_id', 'recordId', 'record_id']);
      final id = rawId ?? _derivedId('record', '$date|$workerId|$toyId|$process|$quantity|$cents');
      if (!seenIds.add(id)) {
        // 同一文件内重复 id，静默跳过，避免主键冲突
        invalid++;
        continue;
      }

      records.add(
        _LegacyRecord(
          id: id,
          date: date,
          workerId: workerId,
          workerName: workerName,
          toyId: toyId,
          toyName: toyName,
          process: process,
          unitPriceTenThousandth: price,
          quantity: quantity,
          subtotalCents: cents,
          remark: _text(item, const ['remark', 'note', 'memo', 'comment']) ?? '',
        ),
      );

      // 记录里出现但档案列表没有的工人/玩具，自动补建
      workers.putIfAbsent(
        workerId,
        () => _LegacyWorker(
          id: workerId,
          name: workerName,
          code: '',
          pinyinInitials: '',
        ),
      );
      toys.putIfAbsent(
        toyId,
        () => _LegacyToy(
          id: toyId,
          name: toyName,
          process: process,
          unitPriceTenThousandth: price,
          pinyinInitials: '',
        ),
      );
    }

    if (records.isEmpty) {
      throw const LegacyImportFailure('旧账文件中没有可导入的有效记录（缺少日期或数量）');
    }

    return _LegacyData(
      workers: workers.values.toList(growable: false),
      toys: toys.values.toList(growable: false),
      records: records,
      invalidCount: invalid,
      warnings: warnings,
    );
  }

  static List<dynamic>? _firstList(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) return value;
    }
    return null;
  }

  static String? _text(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      } else if (value is num) {
        return value.toString();
      }
    }
    return null;
  }

  static int? _int(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(Money.normalizeDigits(value).trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// 单价：优先万分之一元整数，其次「元」（支持小数）。
  static int? _priceTenThousandth(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is int && key.contains('ten_thousandth')) return value;
      if (value is num) {
        if (value is int && key.toLowerCase().contains('tenthousandth')) return value;
        return (value * 10000).round();
      }
      if (value is String) {
        final parsed = Money.tryParsePrice(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// 金额：`*_cents` 直接取分，其余按「元」换算成分。
  static int? _cents(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final isCents = key.toLowerCase().contains('cents');
      if (value is int) {
        return isCents ? value : value * 100;
      }
      if (value is num) {
        return isCents ? value.round() : (value * 100).round();
      }
      if (value is String) {
        final normalized = Money.normalizeDigits(value);
        if (isCents) {
          final parsed = int.tryParse(normalized.trim());
          if (parsed != null) return parsed;
        }
        final parsed = Money.tryParseCents(normalized);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String? _date(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is int) {
        final millis = value < 100000000000 ? value * 1000 : value;
        return Dates.ymd(DateTime.fromMillisecondsSinceEpoch(millis));
      }
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (Dates.isValidYmd(text)) return text;
      final match = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
      if (match != null) {
        final y = match.group(1)!;
        final m = match.group(2)!.padLeft(2, '0');
        final d = match.group(3)!.padLeft(2, '0');
        final candidate = '$y-$m-$d';
        if (Dates.isValidYmd(candidate)) return candidate;
      }
      final millis = int.tryParse(text);
      if (millis != null) {
        final value2 = millis < 100000000000 ? millis * 1000 : millis;
        return Dates.ymd(DateTime.fromMillisecondsSinceEpoch(value2));
      }
    }
    return null;
  }

  /// 没有原 id 时用确定性哈希生成，保证**重复导入仍然幂等**。
  static String _derivedId(String prefix, String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 'legacy-$prefix-${hash.toRadixString(16)}';
  }
}

class _LegacyData {
  const _LegacyData({
    required this.workers,
    required this.toys,
    required this.records,
    required this.invalidCount,
    required this.warnings,
  });

  final List<_LegacyWorker> workers;
  final List<_LegacyToy> toys;
  final List<_LegacyRecord> records;
  final int invalidCount;
  final List<String> warnings;
}

class _LegacyWorker {
  const _LegacyWorker({
    required this.id,
    required this.name,
    required this.code,
    required this.pinyinInitials,
  });

  final String id;
  final String name;
  final String code;
  final String pinyinInitials;
}

class _LegacyToy {
  const _LegacyToy({
    required this.id,
    required this.name,
    required this.process,
    required this.unitPriceTenThousandth,
    required this.pinyinInitials,
  });

  final String id;
  final String name;
  final String process;
  final int unitPriceTenThousandth;
  final String pinyinInitials;
}

class _LegacyRecord {
  const _LegacyRecord({
    required this.id,
    required this.date,
    required this.workerId,
    required this.workerName,
    required this.toyId,
    required this.toyName,
    required this.process,
    required this.unitPriceTenThousandth,
    required this.quantity,
    required this.subtotalCents,
    required this.remark,
  });

  final String id;
  final String date;
  final String workerId;
  final String workerName;
  final String toyId;
  final String toyName;
  final String process;
  final int unitPriceTenThousandth;
  final int quantity;
  final int subtotalCents;
  final String remark;
}
