import 'package:material_ui/material_ui.dart';

import '../../data/models/settlement_event.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 结算状态变更历史面板（审计视图）。
///
/// 只在「工人详情 / 本面板」里展示，打印总表、CSV、工资条都不输出这些记录。
/// 顶部给「当前状态 + 第几次变更 + 最近一次时间」，下面是完整追加流。
Future<void> showSettlementHistorySheet({
  required BuildContext context,
  required AppServices services,
  required String workerId,
  required String workerName,
  required String workerCode,
  required SettlementStatus currentStatus,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SettlementHistorySheet(
      services: services,
      workerId: workerId,
      workerName: workerName,
      workerCode: workerCode,
      currentStatus: currentStatus,
    ),
  );
}

class _SettlementHistorySheet extends StatefulWidget {
  const _SettlementHistorySheet({
    required this.services,
    required this.workerId,
    required this.workerName,
    required this.workerCode,
    required this.currentStatus,
  });

  final AppServices services;
  final String workerId;
  final String workerName;
  final String workerCode;
  final SettlementStatus currentStatus;

  @override
  State<_SettlementHistorySheet> createState() =>
      _SettlementHistorySheetState();
}

class _SettlementHistorySheetState extends State<_SettlementHistorySheet> {
  List<SettlementEvent> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events =
        await widget.services.settlementHistory.listForWorker(widget.workerId);
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _events.isEmpty ? null : _events.first;
    final accent = widget.currentStatus == SettlementStatus.settled
        ? AppTheme.success
        : (widget.currentStatus == SettlementStatus.partial
            ? AppTheme.warning
            : AppTheme.muted);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '变更历史 · ${widget.workerName}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('history-close'),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MutedText(
                widget.workerCode.isEmpty
                    ? '按时间倒序列出每一次结算 / 取消结算'
                    : '${widget.workerCode} · 按时间倒序列出每一次结算 / 取消结算',
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _CurrentStatusCard(
                statusLabel: widget.currentStatus.label,
                count: _events.length,
                latest: latest,
                accent: accent,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _events.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: EmptyState(
                            title: '还没有结算状态变更',
                            hint: '每次标记已结算 / 取消已结算都会在这里追加一条，'
                                '时间戳不会被覆盖。',
                            icon: Icons.history_toggle_off,
                          ),
                        )
                      : ListView.separated(
                          key: const ValueKey('history-list'),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          itemCount: _events.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) =>
                              _HistoryRow(event: _events[index]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: MutedText(
                '这些时间戳、取消理由与变更记录只在详情 / 本历史面板可见，'
                '打印总表与导出的 CSV 不会包含。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前状态标识：状态 + 变更次数 + 最近一次（不覆盖历史）。
class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.statusLabel,
    required this.count,
    required this.latest,
    required this.accent,
  });

  final String statusLabel;
  final int count;
  final SettlementEvent? latest;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = latest;
    final trailText = last == null
        ? '共 0 次变更'
        : '共 $count 次变更 · 最近 ${last.signature} '
            '${last.action.label} 于 ${last.timeText}';
    return Container(
      key: const ValueKey('history-current-status'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                '当前状态：$statusLabel',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            trailText,
            maxLines: 2,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final SettlementEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.isCancellation ? AppTheme.danger : AppTheme.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E9EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                event.signature,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                event.isCancellation
                    ? Icons.undo
                    : Icons.check_circle_outline,
                size: 16,
                color: color,
              ),
              Text(
                event.action.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                event.timeText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            event.detailText,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
