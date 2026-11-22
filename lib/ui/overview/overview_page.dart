import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/piece_record.dart';
import '../../data/models/settlement.dart';
import '../../services/app_services.dart';
import '../../state/selection_scope.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 概览：当日笔数、出勤人数、计件总额 + 最近流水。
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  DayOverview? _today;
  int _monthPieceCents = 0;
  List<PieceRecord> _recent = const [];
  bool _loading = true;
  int _loadedVersion = -1;
  String _loadedDate = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final today = Dates.ymd(DateTime.now());
    if (_loadedVersion != services.refresh.version || _loadedDate != today) {
      _loadedVersion = services.refresh.version;
      _loadedDate = today;
      // 概览只关心「今天」，与录入页选的日期无关
      _load(services, today);
    }
  }

  Future<void> _load(AppServices services, String today) async {
    if (mounted) setState(() => _loading = true);
    final overview = await services.settlements.overview(today);
    final month = await services.settlements.settle(DateRange.thisMonth(DateTime.now()));
    final records = await services.records.listByDate(today);
    if (!mounted) return;
    setState(() {
      _today = overview;
      _monthPieceCents = month.totalPieceCents;
      _recent = records.take(8).toList(growable: false);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final selection = SelectionScope.maybeOf(context);
    final theme = Theme.of(context);
    final today = Dates.ymd(DateTime.now());
    final overview = _today;

    return Scaffold(
      appBar: AppBar(
        title: const Text('概览'),
        centerTitle: false,
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                today,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(services, today),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatBlock(
                    label: '今日笔数',
                    value: '${overview?.recordCount ?? 0}',
                    unit: '笔',
                    icon: Icons.list_alt,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatBlock(
                    label: '出勤人数',
                    value: '${overview?.workerCount ?? 0}',
                    unit: '人',
                    icon: Icons.groups_outlined,
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StatBlock(
              label: '今日计件总额',
              value: Money.formatCents(overview?.pieceCents ?? 0),
              unit: '元',
              icon: Icons.payments_outlined,
              color: const Color(0xFF7A3E00),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '本月累计',
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '计件 ${Money.formatCents(_monthPieceCents)} 元',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        MutedText('${DateTime.now().month} 月 1 日至今，不含调整项'),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final selection = SelectionScope.maybeOf(context);
                      if (selection != null) selection.tabIndex = 2;
                    },
                    child: const Text('看结算'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '快捷操作',
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final target = selection;
                        if (target != null) target.tabIndex = 1;
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('马上计数'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final target = selection;
                        if (target != null) target.tabIndex = 2;
                      },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('去结算'),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '今日流水',
              trailing: _recent.isEmpty
                  ? null
                  : Text(
                      '最近 ${_recent.length} 笔',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.muted),
                    ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _recent.isEmpty
                      ? const EmptyState(
                          title: '今天还没有记账',
                          hint: '到「计数」页选工人和工序，输数量即可',
                          icon: Icons.edit_note,
                        )
                      : Column(
                          children: [
                            for (final record in _recent)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor:
                                          AppTheme.primary.withValues(alpha: 0.1),
                                      child: Text(
                                        record.workerNameSnapshot.characters.first,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(color: AppTheme.primary),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            record.workerNameSnapshot,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            '${record.toyNameSnapshot}'
                                            '${record.processSnapshot == Defaults.defaultProcess ? '' : ' / ${record.processSnapshot}'}'
                                            ' × ${record.quantity}',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      Money.formatCents(record.subtotalCents),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
