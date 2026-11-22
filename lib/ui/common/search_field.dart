import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 行内查找框：流水页与结算页共用同一套交互。
///
/// 统一成一个组件，是为了让"输入姓名或工号 → 匹配数量提示 → 一键清空"
/// 在两个页面上一模一样：车间里换个人操作时不用重新学。
///
/// 只负责输入与清空，过滤逻辑留给调用方（有的按工人过滤，有的按流水过滤）。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.isNotEmpty;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        hintText: hintText,
        hintMaxLines: 2,
        prefixIcon: const Icon(Icons.search, size: 22),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE6E9EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
        ),
        suffixIcon: hasText
            ? IconButton(
                tooltip: '清空查找',
                icon: const Icon(Icons.cancel, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
      ),
      onChanged: onChanged,
    );
  }
}

/// 查找结果提示：`按「张」匹配到 3/200 人` + 清空按钮。
///
/// 空结果也走这里，由调用方在下方再给 EmptyState，
/// 这样"输入了但没匹配到"和"本来就没数据"能被清楚地区分开。
class SearchMatchHint extends StatelessWidget {
  const SearchMatchHint({
    super.key,
    required this.query,
    required this.text,
    this.onClear,
    this.color,
  });

  final String query;
  final String text;
  final VoidCallback? onClear;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? AppTheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.filter_alt_outlined, size: 16, color: accent),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '按「$query」$text',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onClear != null)
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('清空'),
          ),
      ],
    );
  }
}
