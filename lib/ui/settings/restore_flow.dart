import 'package:material_ui/material_ui.dart';

import '../../services/app_services.dart';
import '../common/ui_kit.dart';

/// 从一份备份 JSON 文本恢复账本。
///
/// 本地文件恢复与云端恢复共用这一条路径：
/// 校验 → 展示预览 → 二次确认 → 自动快照 → 事务内覆盖。
/// 返回 true 表示已恢复；校验/恢复失败时抛出 [AppFailure]，由调用方提示。
Future<bool> restoreFromBackupText(
  BuildContext context, {
  required AppServices services,
  required String text,
  String sourceLabel = '本地文件',
}) async {
  final preview = services.backup.inspect(text);
  if (!context.mounted) return false;

  final ok = await showConfirmDialog(
    context,
    title: '用这份备份覆盖当前账本？',
    message: '来源：$sourceLabel\n'
        '备份时间：${preview.summary.exportedAtLabel}\n'
        '流水范围：${preview.summary.dateRangeLabel}\n'
        '工人 ${preview.summary.workerCount} 人 · 玩具 ${preview.summary.toyCount} 项 · '
        '流水 ${preview.summary.recordCount} 笔 · 调整 ${preview.summary.adjustmentCount} 条\n'
        '锁账月份 ${preview.summary.lockedMonthCount} 个\n\n'
        '恢复会先自动备份当前账本，再整体覆盖。现有数据将被替换。',
    confirmText: '确认恢复',
    danger: true,
  );
  if (!ok) return false;

  final result = await services.backup.restore(
    preview,
    persistSafetyBackup: services.files.persistSafetyBackup,
  );
  services.notifyDataChanged();
  if (!context.mounted) return true;
  showToast(
    context,
    '已恢复 ${result.summary.recordCount} 笔流水；恢复前的账本已自动备份',
  );
  return true;
}
