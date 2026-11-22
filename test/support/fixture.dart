import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:toy_piecework/data/db/app_database.dart';
import 'package:toy_piecework/data/models/toy.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/data/repositories/adjustment_repository.dart';
import 'package:toy_piecework/data/repositories/month_lock_repository.dart';
import 'package:toy_piecework/data/repositories/piece_record_repository.dart';
import 'package:toy_piecework/data/repositories/settlement_repository.dart';
import 'package:toy_piecework/data/repositories/toy_repository.dart';
import 'package:toy_piecework/data/repositories/worker_repository.dart';
import 'package:toy_piecework/data/services/backup_service.dart';
import 'package:toy_piecework/data/services/legacy_import_service.dart';
import 'package:toy_piecework/data/services/report_service.dart';

/// 测试夹具：独立临时库 + 全部仓储，一次装配反复使用。
///
/// 注意：不能用 `:memory:`——sqflite_common_ffi 对同一路径会复用同一个连接，
/// 导致不同夹具、不同用例互相污染。
class Fixture {
  Fixture._(this.db, this._tempDir)
      : workers = WorkerRepository(db),
        toys = ToyRepository(db),
        records = PieceRecordRepository(db),
        adjustments = AdjustmentRepository(db),
        months = MonthLockRepository(db),
        settlements = SettlementRepository(db),
        backup = BackupService(db),
        legacy = LegacyImportService(db),
        reports = ReportService(db);

  static Future<Fixture> create() async {
    sqfliteFfiInit();
    final tempDir = await Directory.systemTemp.createTemp('toy_piecework_test_');
    final dbPath = p.join(tempDir.path, 'test.db');
    final db = await AppDatabase.open(
      path: dbPath,
      factoryOverride: databaseFactoryFfi,
    );
    return Fixture._(db, tempDir);
  }

  final AppDatabase db;
  final Directory _tempDir;
  final WorkerRepository workers;
  final ToyRepository toys;
  final PieceRecordRepository records;
  final AdjustmentRepository adjustments;
  final MonthLockRepository months;
  final SettlementRepository settlements;
  final BackupService backup;
  final LegacyImportService legacy;
  final ReportService reports;

  Future<void> dispose() async {
    await db.close();
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
    }
  }

  Future<Worker> addWorker(String name, {String? code}) =>
      workers.create(name: name, code: code);

  Future<Toy> addToy(
    String name, {
    String process = '整件',
    required int priceTenThousandth,
  }) =>
      toys.create(
        name: name,
        process: process,
        unitPriceTenThousandth: priceTenThousandth,
      );
}
