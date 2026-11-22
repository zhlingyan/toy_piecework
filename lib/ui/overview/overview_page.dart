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
import 'attendance_sheet.dart';

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
                    // 出勤 / 总人数；总人数为 0 时安全展示 0/0。
                    value: overview?.attendanceLabel ?? '0/0',
                    unit: '人',
                    icon: Icons.groups_outlined,
                    color: AppTheme.success,
                    onTap: () => showAttendanceSheet(
                      context: context,
                      overview: overview ??
                          DayOverview(
                            date: today,
                            recordCount: 0,
                            workerCount: 0,
                            pieceCents: 0,
                            adjustmentCount: 0,
                          ),
                    ),
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
                    child: _QuickActionButton(
                      label: '马上计数',
                      icon: Icons.add,
                      primary: true,
                      onPressed: () {
                        final target = selection;
                        if (target != null) target.tabIndex = 1;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionButton(
                      label: '去结算',
                      icon: Icons.receipt_long_outlined,
                      onPressed: () {
                        final target = selection;
                        if (target != null) target.tabIndex = 2;
                      },
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

/// 快捷操作按钮：图标与文字强制同一行，杜绝「马上计 / 数」折行。
///
/// 之前用 `FilledButton.icon`，label 在两列窄卡片里会被挤成两行；
/// 这里改成固定高度 + `FittedBox(scaleDown)` + `maxLines: 1`，
/// 字号再大也只会整体缩小、绝不换行。主按钮加渐变与阴影拉开层次，
/// 次按钮与主按钮同高、同圆角、同字重，视觉成一套。
class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final foreground = primary ? Colors.white : AppTheme.primary;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        gradient: primary
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1D64B4), Color(0xFF0F3F78)],
              )
            : null,
        color: primary ? null : AppTheme.surface,
        borderRadius: radius,
        border: primary
            ? null
            : Border.all(
                color: AppTheme.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
        boxShadow: primary
            ? const [
                BoxShadow(
                  color: Color(0x3314549B),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
