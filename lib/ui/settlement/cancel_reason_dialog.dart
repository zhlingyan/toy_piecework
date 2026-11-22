import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 「取消已结算」的理由对话框：**选填**。
///
/// 返回值语义：
/// * `null` → 用户放弃取消（点「先不取消」或点遮罩）；
/// * 任意字符串（含空串 `''`）→ 确认取消，字符串即取消理由。
///
/// 留空也能正常完成，理由只写进变更历史，不进入打印总表。
Future<String?> showCancelSettlementDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确认取消结算',
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    const Text(
                      '取消理由',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '（选填，可留空）',
                      style: TextStyle(fontSize: 14, color: AppTheme.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('cancel-reason-input'),
                  controller: controller,
                  maxLength: 60,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '如：金额算错需重结 / 工人有异议',
                    hintMaxLines: 2,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final preset in const [
                      '算错金额，重结',
                      '工人有异议',
                      '补录后重算',
                      '重复标记',
                    ])
                      ActionChip(
                        label: Text(preset, style: const TextStyle(fontSize: 13)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          controller.text = preset;
                          setDialogState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '留空也能完成取消；理由只记入变更历史，不进入打印总表。',
                  style: TextStyle(fontSize: 13, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('先不取消'),
            ),
            FilledButton(
              key: const ValueKey('cancel-reason-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
              ),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmText),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
