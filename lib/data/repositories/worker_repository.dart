import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../db/app_database.dart';
import '../models/worker.dart';

/// 工人档案仓储。
///
/// 停用采用「归档」而非删除：历史流水、报表、结算仍能关联到人。
class WorkerRepository {
  WorkerRepository(this._db);

  final AppDatabase _db;

  Future<T> _run<T>(
    DatabaseExecutor? ex,
    Future<T> Function(DatabaseExecutor executor) action,
  ) {
    if (ex != null) return action(ex);
    return _db.transaction((txn) => action(txn));
  }

  Future<List<Worker>> listActive({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.workers,
      where: 'is_archived = 0',
      orderBy: 'code ASC, name ASC',
    );
    return rows.map(Worker.fromMap).toList(growable: false);
  }

  Future<List<Worker>> listArchived({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.workers,
      where: 'is_archived = 1',
      orderBy: 'code ASC, name ASC',
    );
    return rows.map(Worker.fromMap).toList(growable: false);
  }

  Future<List<Worker>> listAll({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.workers,
      orderBy: 'is_archived ASC, code ASC, name ASC',
    );
    return rows.map(Worker.fromMap).toList(growable: false);
  }

  Future<Worker?> findById(String id, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.workers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Worker.fromMap(rows.first);
  }

  Future<Worker?> findByCode(String code, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.workers,
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Worker.fromMap(rows.first);
  }

  /// 中文 + 编号 + 拼音首字母混合搜索，`keyword` 为空时返回全部启用档案。
  Future<List<Worker>> search(
    String keyword, {
    bool includeArchived = false,
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final trimmed = keyword.trim();
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('is_archived = 0');
    if (trimmed.isNotEmpty) {
      where.add('(name LIKE ? OR code LIKE ? OR pinyin_initials LIKE ?)');
      final like = '%$trimmed%';
      args
        ..add(like)
        ..add(like)
        ..add(like.toUpperCase());
    }
    final rows = await executor.query(
      Tables.workers,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'code ASC, name ASC',
    );
    return rows.map(Worker.fromMap).toList(growable: false);
  }

  /// 生成下一个显示编号，格式 `W001`。
  Future<String> nextCode({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(Tables.workers, columns: ['code']);
    var maxValue = 0;
    for (final row in rows) {
      final code = (row['code'] as String?) ?? '';
      final match = RegExp(r'(\d+)$').firstMatch(code);
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!) ?? 0;
      if (value > maxValue) maxValue = value;
    }
    return 'W${(maxValue + 1).toString().padLeft(3, '0')}';
  }

  Future<Worker> create({
    required String name,
    String? code,
    String phone = '',
    String idCard = '',
    String pinyinInitials = '',
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) {
        throw const ValidationFailure('工人姓名不能为空');
      }
      final finalCode = (code?.trim().isNotEmpty ?? false)
          ? code!.trim()
          : await nextCode(ex: executor);
      final duplicated = await findByCode(finalCode, ex: executor);
      if (duplicated != null) {
        throw ValidationFailure('编号 $finalCode 已被 ${duplicated.name} 使用');
      }
      final now = AppClock.nowMillis();
      final worker = Worker(
        id: IdGen.next(),
        code: finalCode,
        name: trimmedName,
        phone: phone.trim(),
        idCard: idCard.trim(),
        pinyinInitials: pinyinInitials.trim().toUpperCase(),
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      await executor.insert(Tables.workers, worker.toMap());
      return worker;
    });
  }

  Future<Worker> update(Worker worker, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final trimmedName = worker.name.trim();
      if (trimmedName.isEmpty) {
        throw const ValidationFailure('工人姓名不能为空');
      }
      final existing = await findById(worker.id, ex: executor);
      if (existing == null) {
        throw const ValidationFailure('该工人档案已不存在');
      }
      final newCode = worker.code.trim();
      if (newCode.isNotEmpty && newCode != existing.code) {
        final duplicated = await findByCode(newCode, ex: executor);
        if (duplicated != null && duplicated.id != worker.id) {
          throw ValidationFailure('编号 $newCode 已被 ${duplicated.name} 使用');
        }
      }
      final updated = worker.copyWith(
        name: trimmedName,
        code: newCode.isEmpty ? existing.code : newCode,
        phone: worker.phone.trim(),
        idCard: worker.idCard.trim(),
        pinyinInitials: worker.pinyinInitials.trim().toUpperCase(),
        updatedAt: AppClock.nowMillis(),
      );
      await executor.update(
        Tables.workers,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    });
  }

  /// 停用（归档）或重新启用。
  Future<void> setArchived(
    String id,
    bool archived, {
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      await executor.update(
        Tables.workers,
        {'is_archived': archived ? 1 : 0, 'updated_at': AppClock.nowMillis()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
