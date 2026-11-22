import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/piece_record.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 逐条明细：按当前结算区间，把某工人的每一笔计件与调整项摊开。
///
/// 结算页看到的是「合并后的工序行」，对账时要的是「哪天、几点、干了什么活」。
/// 这里按日期分组、日内按时间倒序，每条都带结算状态，方便当面和工人核对。
class WorkerRecordsPage extends StatefulWidget {
  const WorkerRecordsPage({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.range,
    this.workerCode = '',
  });

  final String workerId;
  final String workerName;
  final String workerCode;
  final DateRange range;

  @override
  State<WorkerRecordsPage> createState() => _WorkerRecordsPageState();
}

/// 一条明细：计件与调整项统一成同一个展示结构。
class _DetailEntry {
  const _DetailEntry({
    required this.date,
    required this.minuteOfDay,
    required this.title,
    required this.subtitle,
    required this.signedCents,
    required this.settled,
    this.tag,
    this.isPiece = true,
    this.overtime = false,
  });

  final String date;
  final int minuteOfDay;
  final String title;
  final String subtitle;
  final int signedCents;
  final bool settled;

  /// 小标签：加班倍率、调整项类型。
  final String? tag;
  final bool isPiece;
  final bool overtime;

  String get month => date.substring(0, 7);

  String get timeLabel => Dates.hhmm(minuteOfDay);
}

class _WorkerRecordsPageState extends State<WorkerRecordsPage> {
  List<_DetailEntry> _entries = const [];
  bool _loading = true;

  /// null = 全部；true = 只看已结算；false = 只看未结算。
  bool? _settledFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.read(context);
    final records = await services.records.listRange(
      widget.range,
      workerId: widget.workerId,
    );
    final adjustments = await services.adjustments.listRange(
      widget.range,
      workerId: widget.workerId,
    );
    final settledMonths =
        await services.settlementMarks.settledMonthsFor(widget.workerId);
    if (!mounted) return;
    setState(() {
      _entries = _buildEntries(records, adjustments, settledMonths);
      _loading = false;
    });
  }

  List<_DetailEntry> _buildEntries(
    List<PieceRecord> records,
    List<Adjustment> adjustments,
    Set<String> settledMonths,
  ) {
    final entries = <_DetailEntry>[
      for (final record in records)
        _DetailEntry(
          date: record.date,
          minuteOfDay: record.minuteOfDay,
          title: record.processSnapshot == Defaults.defaultProcess
              ? record.toyNameSnapshot
              : '${record.toyNameSnapshot} / ${record.processSnapshot}',
          subtitle: '${record.quantity} 件 × ${record.pricingPriceLabel} 元'
              '${record.remark.isEmpty ? '' : ' · ${record.remark}'}',
          signedCents: record.subtotalCents,
          settled: settledMonths.contains(Dates.ymOfYmd(record.date)),
          tag: record.overtime ? '加班 ×${record.overtimeMultiplierLabel}' : null,
          overtime: record.overtime,
        ),
      for (final adjustment in adjustments)
        _DetailEntry(
          date: adjustment.date,
          minuteOfDay: adjustment.minuteOfDay,
          title: adjustment.type.label,
          subtitle: adjustment.summaryLabel,
          signedCents: adjustment.signedCents,
          settled: settledMonths.contains(Dates.ymOfYmd(adjustment.date)),
          isPiece: false,
        ),
    ];

    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      final byTime = b.minuteOfDay.compareTo(a.minuteOfDay);
      if (byTime != 0) return byTime;
      // 同一分钟：计件排在调整项前面，更符合「先干活后记账」的直觉
      if (a.isPiece != b.isPiece) return a.isPiece ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return entries;
  }

  List<_DetailEntry> get _visible {
    final filter = _settledFilter;
    if (filter == null) return _entries;
    return _entries.where((entry) => entry.settled == filter).toList(
          growable: false,
        );
  }

  int _sum(Iterable<_DetailEntry> entries) =>
      entries.fold(0, (sum, entry) => sum + entry.signedCents);

  int get _pieceCents => _sum(_entries.where((entry) => entry.isPiece));

  int get _adjustmentCents => _sum(_entries.where((entry) => !entry.isPiece));

  int get _netCents => _sum(_entries);

  int get _settledCents =>
      _sum(_entries.where((entry) => entry.settled));

  int get _unsettledCents => _netCents - _settledCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.workerName} · 明细'),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _buildSummary(theme),
                  const SizedBox(height: 12),
                  _buildFilter(theme),
                  const SizedBox(height: 6),
                  if (_entries.isEmpty)
                    const EmptyState(
                      title: '这个区间没有明细',
                      hint: '换一个结算区间，或先去「计数」页记几笔',
                      icon: Icons.receipt_long_outlined,
                    )
                  else if (_visible.isEmpty)
                    const EmptyState(
                      title: '当前筛选下没有记录',
                      hint: '切回「全部」看看',
                      icon: Icons.filter_alt_off_outlined,
                    )
                  else
                    for (final group in _groupByDate(_visible).entries)
                      _buildDayCard(theme, group.key, group.value),
                  if (_entries.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: MutedText(
                        '结算状态跟随「工人 + 月份」的标记。'
                        '在工人结算弹层里标记已结算后，这里会同步更新。',
                        align: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Map<String, List<_DetailEntry>> _groupByDate(List<_DetailEntry> entries) {
    final groups = <String, List<_DetailEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.date, () => <_DetailEntry>[]).add(entry);
    }
    return groups;
  }

  Widget _buildSummary(ThemeData theme) {
    final settled = _settledCents;
    final unsettled = _unsettledCents;
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(widget.workerName, style: theme.textTheme.titleLarge),
              if (widget.workerCode.isNotEmpty)
                Text(
                  '编号 ${widget.workerCode}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.muted),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.range.label,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Money.formatCents(_netCents),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: _netCents < 0 ? AppTheme.danger : AppTheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '元 · 合计',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _mini('明细笔数', '${_entries.length}'),
              _mini('计件', Money.formatCents(_pieceCents)),
              _mini(
                '调整',
                Money.formatCentsSigned(_adjustmentCents),
                color: _adjustmentCents == 0
                    ? null
                    : (_adjustmentCents > 0 ? AppTheme.success : AppTheme.danger),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statusBox(
                  '未结算',
                  unsettled,
                  AppTheme.warning,
                  Icons.schedule,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statusBox(
                  '已结算',
                  settled,
                  AppTheme.success,
                  Icons.check_circle_outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, {Color? color}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusBox(String label, int cents, Color color, IconData icon) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${Money.formatCents(cents)} 元',
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilter(ThemeData theme) {
    final unsettled = _entries.where((entry) => !entry.settled).length;
    final settled = _entries.length - unsettled;
    final items = <({bool? value, String label})>[
      (value: null, label: '全部 ${_entries.length}'),
      (value: false, label: '未结算 $unsettled'),
      (value: true, label: '已结算 $settled'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items) ...[
            ChoiceChip(
              label: Text(item.label),
              selected: _settledFilter == item.value,
              onSelected: (_) => setState(() => _settledFilter = item.value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDayCard(
    ThemeData theme,
    String date,
    List<_DetailEntry> entries,
  ) {
    final dayTotal = _sum(entries);
    final weekday = Dates.weekdayLabel(date);
    return SectionCard(
      title: weekday.isEmpty ? date : '$date $weekday',
      trailing: Text(
        '当日 ${Money.formatCentsSigned(dayTotal)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: dayTotal < 0 ? AppTheme.danger : AppTheme.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0) const Divider(height: 16),
            _buildEntryRow(theme, entries[index]),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryRow(ThemeData theme, _DetailEntry entry) {
    final amountColor = entry.isPiece
        ? AppTheme.primary
        : (entry.signedCents >= 0 ? AppTheme.success : AppTheme.danger);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              entry.timeLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (entry.overtime)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          entry.tag ?? '加班',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      entry.title,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (entry.subtitle.isNotEmpty)
                      Text(
                        entry.subtitle,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.muted),
                      ),
                    SettlementBadge(
                      entry.settled
                          ? SettlementStatus.settled
                          : SettlementStatus.unsettled,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                Money.formatCentsSigned(entry.signedCents),
                maxLines: 1,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
