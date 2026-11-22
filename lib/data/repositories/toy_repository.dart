import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../db/app_database.dart';
import '../models/toy.dart';

/// 玩具 + 工序档案仓储。调价只改档案当前价，历史流水靠单价快照不受影响。
class ToyRepository {
  ToyRepository(this._db);

  final AppDatabase _db;

  Future<T> _run<T>(
    DatabaseExecutor? ex,
    Future<T> Function(DatabaseExecutor executor) action,
  ) {
    if (ex != null) return action(ex);
    return _db.transaction((txn) => action(txn));
  }

  Future<List<Toy>> listActive({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.toys,
      where: 'is_archived = 0',
      orderBy: 'name ASC, process ASC',
    );
    return rows.map(Toy.fromMap).toList(growable: false);
  }

  Future<List<Toy>> listArchived({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.toys,
      where: 'is_archived = 1',
      orderBy: 'name ASC, process ASC',
    );
    return rows.map(Toy.fromMap).toList(growable: false);
  }

  Future<List<Toy>> listAll({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.toys,
      orderBy: 'is_archived ASC, name ASC, process ASC',
    );
    return rows.map(Toy.fromMap).toList(growable: false);
  }

  Future<Toy?> findById(String id, {DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.toys,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Toy.fromMap(rows.first);
  }

  /// 建档查重：同名不同工序允许，同名同工序需提醒。
  Future<Toy?> findByNameAndProcess(
    String name,
    String process, {
    DatabaseExecutor? ex,
  }) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.query(
      Tables.toys,
      where: 'name = ? AND process = ?',
      whereArgs: [name.trim(), process.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Toy.fromMap(rows.first);
  }

  Future<List<Toy>> search(
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
      where.add('(name LIKE ? OR process LIKE ? OR pinyin_initials LIKE ?)');
      final like = '%$trimmed%';
      args
        ..add(like)
        ..add(like)
        ..add(like.toUpperCase());
    }
    final rows = await executor.query(
      Tables.toys,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC, process ASC',
    );
    return rows.map(Toy.fromMap).toList(growable: false);
  }

  Future<Toy> create({
    required String name,
    String process = Defaults.defaultProcess,
    required int unitPriceTenThousandth,
    String pinyinInitials = '',
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      final trimmedName = name.trim();
      final trimmedProcess = process.trim().isEmpty ? Defaults.defaultProcess : process.trim();
      if (trimmedName.isEmpty) {
        throw const ValidationFailure('玩具名称不能为空');
      }
      if (unitPriceTenThousandth < 0) {
        throw const ValidationFailure('单价不能为负数');
      }
      final duplicated = await findByNameAndProcess(
        trimmedName,
        trimmedProcess,
        ex: executor,
      );
      if (duplicated != null) {
        throw ValidationFailure(
          '已存在「$trimmedName / $trimmedProcess」档案，请直接使用或改个工序名',
        );
      }
      final now = AppClock.nowMillis();
      final toy = Toy(
        id: IdGen.next(),
        name: trimmedName,
        process: trimmedProcess,
        unitPriceTenThousandth: unitPriceTenThousandth,
        pinyinInitials: pinyinInitials.trim().toUpperCase(),
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      await executor.insert(Tables.toys, toy.toMap());
      return toy;
    });
  }

  Future<Toy> update(Toy toy, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      final trimmedName = toy.name.trim();
      final trimmedProcess = toy.process.trim().isEmpty
          ? Defaults.defaultProcess
          : toy.process.trim();
      if (trimmedName.isEmpty) {
        throw const ValidationFailure('玩具名称不能为空');
      }
      if (toy.unitPriceTenThousandth < 0) {
        throw const ValidationFailure('单价不能为负数');
      }
      final existing = await findById(toy.id, ex: executor);
      if (existing == null) {
        throw const ValidationFailure('该玩具档案已不存在');
      }
      // 名称或工序变化时查重（允许与自己同名）
      if (trimmedName != existing.name || trimmedProcess != existing.process) {
        final duplicated = await findByNameAndProcess(
          trimmedName,
          trimmedProcess,
          ex: executor,
        );
        if (duplicated != null && duplicated.id != toy.id) {
          throw ValidationFailure(
            '已存在「$trimmedName / $trimmedProcess」档案，请改个工序名以免混淆',
          );
        }
      }
      final updated = toy.copyWith(
        name: trimmedName,
        process: trimmedProcess,
        pinyinInitials: toy.pinyinInitials.trim().toUpperCase(),
        updatedAt: AppClock.nowMillis(),
      );
      await executor.update(
        Tables.toys,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    });
  }

  /// 调价：仅影响后续录入，历史流水保留原快照。
  Future<void> updatePrice(
    String id,
    int unitPriceTenThousandth, {
    DatabaseExecutor? ex,
  }) {
    return _run(ex, (executor) async {
      if (unitPriceTenThousandth < 0) {
        throw const ValidationFailure('单价不能为负数');
      }
      await executor.update(
        Tables.toys,
        {
          'unit_price_ten_thousandth': unitPriceTenThousandth,
          'updated_at': AppClock.nowMillis(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> setArchived(String id, bool archived, {DatabaseExecutor? ex}) {
    return _run(ex, (executor) async {
      await executor.update(
        Tables.toys,
        {'is_archived': archived ? 1 : 0, 'updated_at': AppClock.nowMillis()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
