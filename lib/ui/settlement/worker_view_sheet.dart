import 'package:material_ui/material_ui.dart';

import '../../domain/rules/settlement_rules.dart';
import '../../domain/rules/worker_sort.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 「按工人结算」的视图口径：排序 + 状态筛选，收在一个对象里。
///
/// 默认「按金额从高到低 + 全部」，与升级前结算列表的排布最接近；
/// 状态是**筛选**（决定集合），排序只改顺序（不改集合），两者互不干扰。
class WorkerViewOptions {
  const WorkerViewOptions({
    this.sort = WorkerSort.byAmount,
    this.amountDesc = true,
    this.status,
  });

  final WorkerSort sort;
  final bool amountDesc;

  /// null = 全部；unsettled = 未结（含部分已结）；settled = 已结。
  final SettlementStatus? status;

  WorkerViewOptions copyWith({
    WorkerSort? sort,
    bool? amountDesc,
    SettlementStatus? status,
    bool clearStatus = false,
  }) =>
      WorkerViewOptions(
        sort: sort ?? this.sort,
        amountDesc: amountDesc ?? this.amountDesc,
        status: clearStatus ? null : (status ?? this.status),
      );

  String get statusLabel => switch (status) {
        SettlementStatus.unsettled => '未结',
        SettlementStatus.settled => '已结',
        _ => '全部',
      };

  /// 按钮上的紧凑摘要，例如 `金额↓ · 未结`。
  String get summary {
    final sortLabel = switch (sort) {
      WorkerSort.byName => '按人名',
      WorkerSort.byCode => '按工号',
      WorkerSort.byAmount => amountDesc ? '金额↓' : '金额↑',
    };
    return '$sortLabel · $statusLabel';
  }
}

/// 点「排序 / 筛选」单一按钮后弹出的面板。
///
/// 选中即生效：每次改动都会通过 [onChanged] 让背后的页面同步刷新，
/// 关掉面板不需要再手动下拉；面板自己维护 local state，避免重建抖动。
Future<void> showWorkerViewSheet({
  required BuildContext context,
  required WorkerViewOptions current,
  required ValueChanged<WorkerViewOptions> onChanged,
  required int allCount,
  required int settledCount,
  required int unsettledCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _WorkerViewSheet(
          current: current,
          onChanged: onChanged,
          allCount: allCount,
          settledCount: settledCount,
          unsettledCount: unsettledCount,
        ),
      ),
    ),
  );
}

class _WorkerViewSheet extends StatefulWidget {
  const _WorkerViewSheet({
    required this.current,
    required this.onChanged,
    required this.allCount,
    required this.settledCount,
    required this.unsettledCount,
  });

  final WorkerViewOptions current;
  final ValueChanged<WorkerViewOptions> onChanged;
  final int allCount;
  final int settledCount;
  final int unsettledCount;

  @override
  State<_WorkerViewSheet> createState() => _WorkerViewSheetState();
}

class _WorkerViewSheetState extends State<_WorkerViewSheet> {
  late WorkerViewOptions _options = widget.current;

  void _emit(WorkerViewOptions next) {
    setState(() => _options = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('worker-view-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '排序与筛选',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: const ValueKey('worker-view-close'),
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const MutedText(
            '只改变「按工人结算」列表的显示，顶部应付合计始终按全员统计。',
          ),
          const SizedBox(height: 12),
          Text('排序方式',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          for (final sort in WorkerSort.values)
            ListTile(
              key: ValueKey('worker-sort-${sort.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(sort.label),
              subtitle: Text(
                _sortHint(sort),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppTheme.muted),
              ),
              trailing: _options.sort == sort
                  ? const Icon(Icons.radio_button_checked,
                      color: AppTheme.primary)
                  : const Icon(Icons.radio_button_unchecked,
                      color: AppTheme.muted),
              onTap: () => _emit(_options.copyWith(sort: sort)),
            ),
          if (_options.sort == WorkerSort.byAmount) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('worker-amount-desc'),
                  label: const Text('从高到低 ↓'),
                  selected: _options.amountDesc,
                  onSelected: (_) =>
                      _emit(_options.copyWith(amountDesc: true)),
                ),
                ChoiceChip(
                  key: const ValueKey('worker-amount-asc'),
                  label: const Text('从低到高 ↑'),
                  selected: !_options.amountDesc,
                  onSelected: (_) =>
                      _emit(_options.copyWith(amountDesc: false)),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
          Text('结算状态',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('worker-status-all'),
                label: Text('全部 ${widget.allCount}'),
                selected: _options.status == null,
                onSelected: (_) => _emit(_options.copyWith(clearStatus: true)),
              ),
              ChoiceChip(
                key: const ValueKey('worker-status-settled'),
                label: Text('已结 ${widget.settledCount}'),
                selected: _options.status == SettlementStatus.settled,
                onSelected: (_) => _emit(_options.copyWith(
                  status: SettlementStatus.settled,
                )),
              ),
              ChoiceChip(
                key: const ValueKey('worker-status-unsettled'),
                label: Text('未结 ${widget.unsettledCount}'),
                selected: _options.status == SettlementStatus.unsettled,
                onSelected: (_) => _emit(_options.copyWith(
                  status: SettlementStatus.unsettled,
                )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const MutedText(
            '「已结 / 未结」是筛选：只列出对应状态的工人；排序只改顺序，'
            '查找只按姓名 / 工号定位。三者可以叠加，互不冲突。',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                key: const ValueKey('worker-view-reset'),
                onPressed: () => _emit(const WorkerViewOptions()),
                child: const Text('恢复默认'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('worker-view-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sortHint(WorkerSort sort) => switch (sort) {
        WorkerSort.byName => '按姓名拼音首字母 + 姓名排序',
        WorkerSort.byCode => '工号按数值排：A2 在 A10 前、002 在 010 前',
        WorkerSort.byAmount => '按本期应付（总付）金额排序，可切换方向',
      };
}
