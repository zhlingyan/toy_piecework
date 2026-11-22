import 'package:material_ui/material_ui.dart';

import '../../domain/pinyin/pinyin_helper.dart';
import '../theme.dart';

/// 档案选择器：支持中文 / 拼音首字母 / 编号混合搜索，按 A–Z 分组。
///
/// 返回选中的原始对象（调用方用它拿固定 id，绝不用下标）。
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T item) nameOf,
  required String Function(T item) subtitleOf,
  required String Function(T item) initialsOf,
  String Function(T item)? codeOf,
  String Function(T item)? badgeOf,
  String hintText = '输入姓名或首字母，如 zs',
  String emptyHint = '没有匹配的档案',
  String? emptyActionHint,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _PickerSheet<T>(
      title: title,
      items: items,
      nameOf: nameOf,
      subtitleOf: subtitleOf,
      initialsOf: initialsOf,
      codeOf: codeOf,
      badgeOf: badgeOf,
      hintText: hintText,
      emptyHint: emptyHint,
      emptyActionHint: emptyActionHint,
    ),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.nameOf,
    required this.subtitleOf,
    required this.initialsOf,
    required this.hintText,
    required this.emptyHint,
    this.codeOf,
    this.badgeOf,
    this.emptyActionHint,
  });

  final String title;
  final List<T> items;
  final String Function(T) nameOf;
  final String Function(T) subtitleOf;
  final String Function(T) initialsOf;
  final String Function(T)? codeOf;
  final String Function(T)? badgeOf;
  final String hintText;
  final String emptyHint;
  final String? emptyActionHint;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.items.where((item) {
      return PinyinHelper.matches(
        query: _query,
        name: widget.nameOf(item),
        initials: widget.initialsOf(item),
        code: widget.codeOf?.call(item) ?? '',
      );
    }).toList(growable: false);

    // 展平成「分组标题 + 条目」列表，便于 ListView 复用
    final rows = <Object>[];
    final grouped = PinyinHelper.groupByInitial<T>(
      filtered,
      initialsOf: widget.initialsOf,
      codeOf: (item) => widget.codeOf?.call(item) ?? '',
      nameOf: widget.nameOf,
    );
    grouped.forEach((group, list) {
      rows.add(group);
      rows.addAll(list.cast<Object>());
    });

    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SizedBox(
        height: mediaQuery.size.height * 0.82,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD5D9E0),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '共 ${widget.items.length} 个',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search, size: 24),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off,
                              size: 44, color: Color(0xFFB6BDC9)),
                          const SizedBox(height: 10),
                          Text(widget.emptyHint,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: AppTheme.muted)),
                          if (widget.emptyActionHint != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.emptyActionHint!,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppTheme.muted),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return Container(
                            color: const Color(0xFFF3F5F8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 6),
                            child: Text(
                              row,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }
                        final item = row as T;
                        final badge = widget.badgeOf?.call(item);
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          title: Text(
                            widget.nameOf(item),
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            widget.subtitleOf(item),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.muted),
                          ),
                          trailing: badge == null
                              ? null
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    badge,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

