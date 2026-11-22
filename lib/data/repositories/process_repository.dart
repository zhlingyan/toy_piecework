import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/failures.dart';
import '../db/app_database.dart';
import '../db/schema.dart';
import '../models/process_preset.dart';

/// 工序选项仓储：预置项 + 用户自定义项。
///
/// 设计要点：
/// * `name` 是主键，靠数据库唯一性挡住「大小写不同但内容一样」之外的重复；
/// * 预置项用 `INSERT OR IGNORE` 灌入，建库 / 升级 / 恢复三条路径都能安全重跑；
/// * 自定义项一旦被玩具档案引用就不允许删除，避免历史流水里的工序名突然失去来源。
class ProcessRepository {
  ProcessRepository(this._db);

  final AppDatabase _db;

  /// 全部工序，预置项在前（按预置顺序），自定义项在后（按加入时间）。
  Future<List<ProcessPreset>> listAll({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.processPresets,
      orderBy: 'is_builtin DESC, sort_order ASC, created_at ASC, name ASC',
    );
    return rows.map(ProcessPreset.fromMap).toList(growable: false);
  }

  /// 只取名字，给选择列表用。
  Future<List<String>> listNames({DatabaseExecutor? ex}) async {
    final presets = await listAll(ex: ex);
    return presets.map((item) => item.name).toList(growable: false);
  }

  /// 补齐预置项。建库、升级、恢复之后都可以安全调用。
  Future<void> ensureSeeded({DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor executor) async {
      for (final statement in Schema.seedProcessStatements) {
        await executor.execute(statement);
      }
    }

    if (ex != null) return run(ex);
    await _db.transaction(run);
  }

  /// 新增自定义工序，返回落库后的名字（已存在则直接返回原有名字）。
  ///
  /// 允许和预置项重名：此时视为「选中已有的那个」，不重复插入。
  Future<String> addCustom(String name, {DatabaseExecutor? ex}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationFailure('工序名称不能为空');
    }
    if (trimmed.runes.length > Limits.maxProcessNameLength) {
      throw ValidationFailure('工序名称最多 ${Limits.maxProcessNameLength} 个字');
    }

    Future<String> run(DatabaseExecutor executor) async {
      final existing = await executor.query(
        Tables.processPresets,
        columns: ['name'],
        where: 'name = ?',
        whereArgs: [trimmed],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first['name']! as String;

      await executor.insert(
        Tables.processPresets,
        {
          'name': trimmed,
          'is_builtin': 0,
          'sort_order': 0,
          'created_at': AppClock.nowMillis(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return trimmed;
    }

    if (ex != null) return run(ex);
    return _db.transaction(run);
  }

  /// 这个工序是否已被玩具档案使用。
  Future<bool> isUsedByToys(String name, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.toys} WHERE process = ?',
      [name],
    );
    return ((rows.first['c'] as int?) ?? 0) > 0;
  }

  /// 删除自定义工序。预置项、已被引用的项都不允许删。
  Future<void> removeCustom(String name, {DatabaseExecutor? ex}) async {
    Future<void> run(DatabaseExecutor executor) async {
      final rows = await executor.query(
        Tables.processPresets,
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const ValidationFailure('这个工序已经不存在');
      }
      if (((rows.first['is_builtin'] as int?) ?? 0) != 0) {
        throw const ValidationFailure('预置工序不能删除');
      }
      final used = await isUsedByToys(name, ex: executor);
      if (used) {
        throw const ValidationFailure('已经有玩具档案在用这个工序，不能删除');
      }
      await executor.delete(
        Tables.processPresets,
        where: 'name = ? AND is_builtin = 0',
        whereArgs: [name],
      );
    }

    if (ex != null) return run(ex);
    await _db.transaction(run);
  }
}
