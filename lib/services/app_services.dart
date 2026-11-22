import 'package:material_ui/material_ui.dart';

import '../data/db/app_database.dart';
import '../data/repositories/adjustment_repository.dart';
import '../data/repositories/month_lock_repository.dart';
import '../data/repositories/piece_record_repository.dart';
import '../data/repositories/process_repository.dart';
import '../data/repositories/settlement_entry_repository.dart';
import '../data/repositories/settlement_history_repository.dart';
import '../data/repositories/settlement_mark_repository.dart';
import '../data/repositories/settlement_repository.dart';
import '../data/repositories/toy_repository.dart';
import '../data/repositories/worker_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/cloud_backup_service.dart';
import '../data/services/csv_export_service.dart';
import '../data/services/legacy_import_service.dart';
import '../data/services/payslip_service.dart';
import '../data/services/report_service.dart';
import 'app_settings.dart';
import 'file_service.dart';

/// 数据变更广播：档案或流水变动后，各页面据此刷新。
class AppRefresh extends ChangeNotifier {
  int _version = 0;

  int get version => _version;

  void bump() {
    _version++;
    notifyListeners();
  }
}

/// 服务容器：一次构建，全树共享。
class AppServices {
  AppServices({required this.db, required this.settings})
      : workers = WorkerRepository(db),
        toys = ToyRepository(db),
        records = PieceRecordRepository(
          db,
          history: SettlementHistoryRepository(db),
        ),
        adjustments = AdjustmentRepository(
          db,
          history: SettlementHistoryRepository(db),
        ),
        processes = ProcessRepository(db),
        months = MonthLockRepository(db),
        settlements = SettlementRepository(db),
        settlementMarks = SettlementMarkRepository(db),
        settlementHistory = SettlementHistoryRepository(db),
        backup = BackupService(db),
        legacy = LegacyImportService(db),
        reports = ReportService(db),
        csv = const CsvExportService(),
        payslips = const PayslipService() {
    cloud = CloudBackupService(db, backup, () => settings.lastCloudBackupAt);
    settlementEntries =
        SettlementEntryRepository(db, settlementMarks, settlementHistory);
  }

  final AppDatabase db;
  final AppSettings settings;
  final AppRefresh refresh = AppRefresh();
  final FileService files = FileService();

  final WorkerRepository workers;
  final ToyRepository toys;
  final PieceRecordRepository records;
  final AdjustmentRepository adjustments;
  final ProcessRepository processes;
  final MonthLockRepository months;
  final SettlementRepository settlements;
  final SettlementMarkRepository settlementMarks;

  /// 状态变更历史：只追加，供详情/历史面板查看，不参与金额与打印总表。
  final SettlementHistoryRepository settlementHistory;

  /// 逐笔结算：在整月标记之上提供"这一笔已结/未结"的细粒度操作。
  late final SettlementEntryRepository settlementEntries;
  final BackupService backup;
  final LegacyImportService legacy;
  final ReportService reports;
  final CsvExportService csv;
  final PayslipService payslips;

  /// 云备份依赖「上次成功时间」，必须在构造体内创建。
  late final CloudBackupService cloud;

  void notifyDataChanged() => refresh.bump();

  Future<void> dispose() async {
    refresh.dispose();
    await db.close();
  }
}

/// 通过 InheritedWidget 向下传递服务，避免每个页面都写构造注入。
class AppScope extends InheritedNotifier<AppRefresh> {
  const AppScope({
    super.key,
    required this.services,
    required AppRefresh refresh,
    required super.child,
  }) : super(notifier: refresh);

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, '缺少 AppScope');
    return scope!.services;
  }

  /// 不订阅变更时使用（例如在回调里读取服务）。
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, '缺少 AppScope');
    return scope!.services;
  }
}
