import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../services/app_services.dart';
import '../theme.dart';
import 'ui_kit.dart';

/// CSV 导出：让用户在「存到手机」和「发给别人」之间选一个。
///
/// 文本在调用前就已经带好 UTF-8 BOM，这里只负责落地方式。
Future<void> showCsvExportSheet(
  BuildContext context, {
  required String csv,
  required String fileName,
  String title = '导出表格',
}) async {
  final services = AppScope.read(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              title,
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _SheetAction(
            icon: Icons.save_alt,
            title: '保存到手机',
            subtitle: '存到「文件」里，可用 Excel / WPS 打开',
            onTap: () => Navigator.of(sheetContext).pop('save'),
          ),
          _SheetAction(
            icon: Icons.ios_share,
            title: '发送给他人',
            subtitle: '通过微信、QQ、邮件等发送表格文件',
            onTap: () => Navigator.of(sheetContext).pop('share'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;

  try {
    if (choice == 'save') {
      final uri = await services.files.exportText(
        csv,
        fileName,
        mimeType: 'text/csv',
      );
      if (!context.mounted) return;
      if (uri != null) {
        showToast(context, '已保存：$fileName');
      }
    } else {
      final path = await services.files.writeTempText(csv, fileName);
      await services.files.shareFiles([path], subject: fileName);
    }
  } catch (error) {
    if (!context.mounted) return;
    showToast(context, '导出失败：$error', isError: true);
  }
}

/// 工资条预览：单页直接展示，多页可左右滑动翻页。
///
/// 图片在进入这里之前已经由 [PayslipService] 分页渲染完毕，
/// 因此预览只持有字节，不再做一次全量渲染，避免大账 OOM。
Future<void> showPayslipSheet(
  BuildContext context, {
  required List<Uint8List> images,
  required String workerName,
}) async {
  if (images.isEmpty) return;
  final services = AppScope.read(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _PayslipSheet(
      images: images,
      workerName: workerName,
      services: services,
    ),
  );
}

class _PayslipSheet extends StatefulWidget {
  const _PayslipSheet({
    required this.images,
    required this.workerName,
    required this.services,
  });

  final List<Uint8List> images;
  final String workerName;
  final AppServices services;

  @override
  State<_PayslipSheet> createState() => _PayslipSheetState();
}

class _PayslipSheetState extends State<_PayslipSheet> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _namePrefix {
    final stamp = DateTime.now();
    return '工资条-${widget.workerName}-'
        '${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.services.files.saveImagesToGallery(
        widget.images,
        namePrefix: _namePrefix,
      );
      if (!mounted) return;
      showToast(
        context,
        widget.images.length > 1
            ? '已保存 ${widget.images.length} 张图到相册'
            : '已保存到相册',
      );
    } catch (error) {
      if (!mounted) return;
      showToast(context, '$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final paths = <String>[];
      for (var index = 0; index < widget.images.length; index++) {
        final suffix = widget.images.length == 1 ? '' : '-${index + 1}';
        paths.add(
          await widget.services.files.writeTempImage(
            widget.images[index],
            '$_namePrefix$suffix.png',
          ),
        );
      }
      await widget.services.files.shareFiles(
        paths,
        text: '${widget.workerName} 的工资条',
        subject: _namePrefix,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(context, '分享失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.78;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.workerName} 的工资条',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.images.length > 1)
                  Text(
                    '${_page + 1} / ${widget.images.length}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.muted),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => InteractiveViewer(
                maxScale: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Image.memory(
                    widget.images[index],
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: MutedText(
                '明细较长，已自动拆成 ${widget.images.length} 张图，左右滑动查看',
                align: TextAlign.center,
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('存到相册'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _share,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share),
                      label: const Text('发给工人'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 26),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
      ),
      onTap: onTap,
    );
  }
}
