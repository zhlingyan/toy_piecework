import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/services/cloud_backup_service.dart';
import '../../services/app_services.dart';

/// 前台静默备份闸门。
///
/// 只在两个时机检查一次：应用启动、从后台回到前台。
/// 不用后台定时器——Android 会杀后台任务，定时器既不可靠又费电。
/// 任何失败都只记录状态，绝不打断记账。
class AutoBackupGate extends StatefulWidget {
  const AutoBackupGate({super.key, required this.child});

  final Widget child;

  @override
  State<AutoBackupGate> createState() => _AutoBackupGateState();
}

class _AutoBackupGateState extends State<AutoBackupGate>
    with WidgetsBindingObserver {
  bool _running = false;
  bool _cleanedTemp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧之后再跑，避免和启动时的数据库初始化抢资源
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRun());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRun();
    }
  }

  Future<void> _maybeRun() async {
    if (!mounted || _running) return;
    final services = AppScope.read(context);

    if (!_cleanedTemp) {
      _cleanedTemp = true;
      unawaited(services.files.cleanTempShares());
    }

    if (!services.settings.cloudAutoEnabled) return;

    _running = true;
    try {
      final result = await services.cloud.autoBackup();
      switch (result.status) {
        case AutoBackupStatus.uploaded:
          await services.settings.markCloudBackupSuccess();
          await services.cloud.cleanupAutoBackups();
        case AutoBackupStatus.failed:
          await services.settings.markCloudBackupFailure(
            result.message ?? '备份失败',
          );
        case AutoBackupStatus.disabled:
        case AutoBackupStatus.noConfig:
        case AutoBackupStatus.notDue:
        case AutoBackupStatus.noChanges:
          break;
      }
    } catch (_) {
      // 自动备份永远不向用户抛错：失败原因已写进设置页状态
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
