import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../data/models/process_preset.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 工序选择器：点开就从常用项里挑，找不到再新增。
///
/// 返回值是选中的工序名（新增的那一项会立刻被选中并返回）。
/// 新增项已落库，下次打开就在列表里，不用再打一遍。
Future<String?> showProcessPicker({
  required BuildContext context,
  required AppServices services,
  String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _ProcessPickerSheet(
        services: services,
        current: current,
      ),
    ),
  );
}

class _ProcessPickerSheet extends StatefulWidget {
  const _ProcessPickerSheet({required this.services, this.current});

  final AppServices services;
  final String? current;

  @override
  State<_ProcessPickerSheet> createState() => _ProcessPickerSheetState();
}

class _ProcessPickerSheetState extends State<_ProcessPickerSheet> {
  final TextEditingController _search = TextEditingController();

  List<ProcessPreset> _items = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (!mounted) return;
      setState(() => _query = _search.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await widget.services.processes.listAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<ProcessPreset> get _filtered {
    if (_query.isEmpty) return _items;
    return _items
        .where((item) =>
            item.name.contains(_query) ||
            item.name.toUpperCase().contains(_query.toUpperCase()))
        .toList(growable: false);
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新增工序'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: Limits.maxProcessNameLength,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            labelText: '工序名称',
            hintText: '如：打眼 / 烫标 / 穿吊牌',
            helperText: '加过一次就会留在列表里，以后直接点',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    final name = input?.trim() ?? '';
    if (name.isEmpty || !mounted) return;
    try {
      final saved = await widget.services.processes.addCustom(name);
      widget.services.notifyDataChanged();
      if (!mounted) return;
      // 新增完直接用上：用户点「新增」就是为了记这一笔
      Navigator.of(context).pop(saved);
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '保存失败：$error', isError: true);
    }
  }

  Future<void> _deleteCustom(ProcessPreset item) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除工序「${item.name}」？',
      message: '只是从常用列表里移除，已经记过的流水和档案不受影响。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.services.processes.removeCustom(item.name);
      widget.services.notifyDataChanged();
      await _load();
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filtered;
    final height = MediaQuery.of(context).size.height * 0.78;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD5D9E0),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('选择工序', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MutedText('常用工序直接点；没有合适的就点「新增工序」，加一次以后都在。'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索工序，如 缝头',
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextButton.icon(
              onPressed: _addCustom,
              icon: const Icon(Icons.add),
              label: const Text('新增工序'),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? EmptyState(
                        title: _items.isEmpty ? '还没有工序' : '没有匹配的工序',
                        hint: _items.isEmpty
                            ? '点上面的「新增工序」添加第一个'
                            : '换个词搜，或点「新增工序」加一个',
                        icon: Icons.search_off,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected = item.name == widget.current;
                          return ListTile(
                            title: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? AppTheme.primary : null,
                              ),
                            ),
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color:
                                  selected ? AppTheme.primary : AppTheme.muted,
                            ),
                            subtitle: item.isBuiltin
                                ? null
                                : Text(
                                    item.badge,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: AppTheme.muted),
                                  ),
                            trailing: item.isBuiltin
                                ? null
                                : IconButton(
                                    tooltip: '删除这个工序',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: AppTheme.muted,
                                    ),
                                    onPressed: () => _deleteCustom(item),
                                  ),
                            onTap: () => Navigator.of(context).pop(item.name),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
