import 'package:material_ui/material_ui.dart';

import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/piece_record.dart';
import '../../domain/rules/trash_rules.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 回收站：删除 30 天内可恢复；超期记录由数据层隐藏，不物理删除。
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<PieceRecord> _records = const [];
  List<Adjustment> _adjustments = const [];
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final records = await services.records.listTrash();
    final adjustments = await services.adjustments.listTrash();
    if (!mounted) return;
    setState(() {
      _records = records;
      _adjustments = adjustments;
      _loading = false;
    });
  }

  Future<void> _restoreRecord(PieceRecord record) async {
    final services = AppScope.of(context);
    try {
      await services.records.restore(record.id);
      services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(context, '已恢复到 ${record.date} 的流水');
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  Future<void> _restoreAdjustment(Adjustment adjustment) async {
    final services = AppScope.of(context);
    try {
      await services.adjustments.restore(adjustment.id);
      services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(context, '已恢复${adjustment.type.label} ${adjustment.amountLabel} 元');
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('回收站'),
          backgroundColor: AppTheme.surface,
          surfaceTintColor: Colors.transparent,
          bottom: const TabBar(
            labelStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(fontSize: 17),
            tabs: [
              Tab(text: '计件流水'),
              Tab(text: '调整项'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: InfoBanner(
                      text: '删除后 30 天内可一键恢复；超过 30 天的记录会自动隐藏且不可恢复，'
                          '但数据库仍保留痕迹用于对账。',
                      color: AppTheme.primary,
                      icon: Icons.info_outline,
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildRecordList(theme),
                        _buildAdjustmentList(theme),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRecordList(ThemeData theme) {
    if (_records.isEmpty) {
      return const EmptyState(
        title: '回收站里没有计件记录',
        hint: '删除的流水会先放这里，30 天后自动隐藏',
        icon: Icons.delete_outline,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = _records[index];
        final remaining = TrashPolicy.remainingDays(record.deletedAt!);
        return SectionCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.workerNameSnapshot} · ${record.toyNameSnapshot}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.date} · ${record.quantity} 件 × ${record.priceLabel}'
                      ' = ${Money.formatCents(record.subtotalCents)} 元',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '剩余 $remaining 天可恢复',
                      style: const TextStyle(fontSize: 13, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _restoreRecord(record),
                child: const Text('恢复'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdjustmentList(ThemeData theme) {
    if (_adjustments.isEmpty) {
      return const EmptyState(
        title: '回收站里没有调整项',
        hint: '删除的补贴/计时/扣款/预支会先放这里',
        icon: Icons.delete_outline,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _adjustments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final adjustment = _adjustments[index];
        final remaining = TrashPolicy.remainingDays(adjustment.deletedAt!);
        return SectionCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${adjustment.workerNameSnapshot} · ${adjustment.type.label} '
                      '${Money.formatCents(adjustment.amountCents)} 元',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${adjustment.date} · ${adjustment.remark}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '剩余 $remaining 天可恢复',
                      style: const TextStyle(fontSize: 13, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _restoreAdjustment(adjustment),
                child: const Text('恢复'),
              ),
            ],
          ),
        );
      },
    );
  }
}
