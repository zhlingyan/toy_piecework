import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../domain/rules/date_periods.dart';
import '../theme.dart';

/// 区间选择结果。[custom] 为 true 时表示用户点了"自定义区间"，
/// 调用方需要再拉起日期范围选择器。
class RangePick {
  const RangePick(this.range, {this.custom = false});

  final DateRange range;
  final bool custom;
}

/// 弹出完整的时间区间列表（本周 / 上周 / 这个月 … / 这一年 / 上一年）。
///
/// 为什么从"一排小圆片"改成列表：区间一层套一层（周→月→季度→半年→年），
/// 平铺十几个按钮既挤又难找，而且没人记得住"这个季度"到底是哪三个月。
/// 列表里每一项都带**起止日期**，选之前就能看清，选完立刻生效。
Future<RangePick?> showRangePickerSheet({
  required BuildContext context,
  required DateRange current,
  required DateTime now,
}) {
  return showModalBottomSheet<RangePick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _RangePickerSheet(current: current, now: now),
  );
}

class _RangePickerSheet extends StatelessWidget {
  const _RangePickerSheet({required this.current, required this.now});

  final DateRange current;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = DatePeriods.groups(now);
    final matched = DatePeriods.match(current, now);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
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
                  child: Text('选择时间区间', style: theme.textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '按自然日历计算：周一到周日、自然月、自然季度（Q1–Q4）；'
              '「这半年」是当前所在的 1–6 月或 7–12 月。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
                height: 1.45,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final group in groups) ...[
                  Container(
                    color: const Color(0xFFF3F5F8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 7,
                    ),
                    child: Text(
                      group.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final option in group.options)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 2,
                      ),
                      selected: matched?.key == option.key,
                      title: Text(
                        option.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        option.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                      trailing: matched?.key == option.key
                          ? const Icon(Icons.check_circle, color: AppTheme.primary)
                          : const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
                      onTap: () => Navigator.of(context).pop(
                        RangePick(option.range),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // 自定义区间：与列表快捷项并列，选中后回填到同一个入口
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            leading: const Icon(Icons.date_range, color: AppTheme.primary),
            title: const Text('自定义区间'),
            subtitle: Text(
              '自己选起止日期，当前 ${Dates.rangeLabel(current.start, current.end)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
            trailing: matched == null
                ? const Icon(Icons.check_circle, color: AppTheme.primary)
                : const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
            onTap: () => Navigator.of(context).pop(
              RangePick(current, custom: true),
            ),
          ),
        ],
      ),
    );
  }
}
