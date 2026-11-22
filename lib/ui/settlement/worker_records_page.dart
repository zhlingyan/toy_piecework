import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/piece_record.dart';
import '../../data/models/settlement_state.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../../domain/rules/backfill_rules.dart';
import '../../domain/rules/price_rules.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../common/record_time_sheet.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 逐条明细：按当前结算区间，把某工人的每一笔计件与调整项摊开。
///
/// 结算页看到的是「合并后的工序行」，对账时要的是「哪天、几点、干了什么活」。
/// 这里按日期分组、日内按时间倒序，每条都带结算状态，方便当面和工人核对。
///
/// ## 三个标签各有分工
///
/// * **加班 ×1.5**：这一笔按加班价算的；
/// * **临时调价**：这一笔的单价与档案不同（档案本身没被改）；
/// * **补录 N 天**：今天录的、账算在更早的日期（红色）。
///
/// ## 两个时间必须分清
///
/// * **归属日期**（`date`）：这笔活算哪一天，分组、统计、结算都按它；
/// * **录入时间**（`createdAt`）：什么时候按的保存键。
///
/// 今天录了 11 号的活 → 这笔显示在 **11 号**那一组下面（不是今天），
/// 同时打上红色「补录」角标；点这一行能看到精确到秒的录入时间。
///
/// ## 逐笔结算
///
/// 每行右侧有「结算 / 取消」小按钮：结工资时不必整期一刀切，
/// 谁先结清就先勾谁，汇总卡会立刻跟着变。
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
    required this.id,
    required this.date,
    required this.minuteOfDay,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    required this.signedCents,
    required this.settled,
    this.settledIndividually = false,
    this.tag,
    this.remark = '',
    this.isPiece = true,
    this.overtime = false,
    this.tempPrice = false,
  });

  /// 主键：逐笔结算要拿它去更新对应那一条。
  final String id;

  /// 业务日期（归属日）。
  final String date;

  /// 业务时刻。
  final int minuteOfDay;

  /// 录入时间（毫秒时间戳），只用于审计展示。
  final int createdAt;

  final String title;
  final String subtitle;
  final int signedCents;
  final bool settled;

  /// 是否被**单独**标记结算（false 而 [settled] 为 true 表示跟随整月标记）。
  final bool settledIndividually;

  /// 小标签：加班倍率、调整项类型。
  final String? tag;
  final String remark;
  final bool isPiece;
  final bool overtime;

  /// 单价与档案不一致（临时调价）。
  final bool tempPrice;

  String get month => date.substring(0, 7);

  String get timeLabel => Dates.hhmm(minuteOfDay);

  /// 是不是「今天补录的前面日期」。
  bool isBackfill(String today) => BackfillRules.isBackfill(
        workDate: date,
        createdAtMillis: createdAt,
        today: today,
      );

  int daysEarlier(String today) => Dates.daysBetween(date, today);
}

class _WorkerRecordsPageState extends State<WorkerRecordsPage> {
  List<_DetailEntry> _entries = const [];
  bool _loading = true;

  /// 正在提交单笔结算的位置，避免连点重复提交。
  bool _busy = false;

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
    final settlementState = await services.settlementMarks.loadState();
    final toys = await services.toys.listAll();
    if (!mounted) return;
    setState(() {
      _entries = _buildEntries(
        records,
        adjustments,
        settlementState,
        {for (final toy in toys) toy.id: toy.unitPriceTenThousandth},
      );
      _loading = false;
    });
  }

  List<_DetailEntry> _buildEntries(
    List<PieceRecord> records,
    List<Adjustment> adjustments,
    SettlementState settlementState,
    Map<String, int> basePrices,
  ) {
    final entries = <_DetailEntry>[
      for (final record in records)
        _DetailEntry(
          id: record.id,
          // 分组只用 record.date；createdAt 只进审计字段
          date: record.workDate,
          minuteOfDay: record.minuteOfDay,
          createdAt: record.createdAt,
          title: record.processSnapshot == Defaults.defaultProcess
              ? record.toyNameSnapshot
              : '${record.toyNameSnapshot} / ${record.processSnapshot}',
          subtitle: '${record.quantity} 件 × ${record.pricingPriceLabel}'
              '${record.remark.isEmpty ? '' : ' · ${record.remark}'}',
          signedCents: record.subtotalCents,
          settled: settlementState.isPieceSettled(record),
          settledIndividually: record.settledIndividually,
          tag: record.overtime ? '加班 ×${record.overtimeMultiplierLabel}' : null,
          remark: record.remark,
          overtime: record.overtime,
          tempPrice: PriceRules.isTemporary(
            recordUnitPrice: record.unitPriceSnapshot,
            baseUnitPrice: basePrices[record.toyId] ?? 0,
          ),
        ),
      for (final adjustment in adjustments)
        _DetailEntry(
          id: adjustment.id,
          date: adjustment.workDate,
          minuteOfDay: adjustment.minuteOfDay,
          createdAt: adjustment.createdAt,
          title: adjustment.type.label,
          subtitle: adjustment.summaryLabel,
          signedCents: adjustment.signedCents,
          settled: settlementState.isAdjustmentSettled(adjustment),
          settledIndividually: adjustment.settledIndividually,
          remark: adjustment.remark,
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

  String get _today => Dates.ymd(AppClock.now());

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

  int get _settledCount => _entries.where((entry) => entry.settled).length;

  /// 今天补录的笔数。
  int get _backfillCount =>
      _entries.where((entry) => entry.isBackfill(_today)).length;

  /// 单笔切换结算状态。
  ///
  /// 走 [SettlementEntryRepository]：它会在需要时把「整月标记」展开成逐笔标记，
  /// 否则整月已结的月份里取消某一笔，刷新后又会变回已结算。
  Future<void> _toggleSettled(_DetailEntry entry) async {
    if (_busy) return;
    final settle = !entry.settled;
    if (!settle && entry.settledIndividually == false) {
      // 由整月标记带来的已结算：取消这一笔等于把整月拆成逐笔，先说清楚
      final ok = await showConfirmDialog(
        context,
        title: '取消这一笔的结算？',
        message: '这个月整月都标记了已结算。取消这一笔会把它拆成逐笔记录，'
            '其余各笔仍是已结算。\n金额不变，随时可以再标回来。',
        confirmText: '取消这一笔',
        danger: true,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final services = AppScope.read(context);
      if (entry.isPiece) {
        await services.settlementEntries
            .setRecordSettled(entry.id, settled: settle);
      } else {
        await services.settlementEntries
            .setAdjustmentSettled(entry.id, settled: settle);
      }
      services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(
        context,
        settle
            ? '已标记这一笔为已结算（${Money.formatCentsSigned(entry.signedCents)}）'
            : '已取消这一笔的结算标记',
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _today;
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
                  _buildSummary(theme, today),
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
                      _buildDayCard(theme, group.key, group.value, today),
                  if (_entries.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const MutedText(
                      '右侧「结算 / 取消」可以逐笔改状态：整期发了就整期标，'
                      '谁先结清就先勾谁，上面的金额会立刻跟着变。',
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const MutedText(
                      '红色「补录」= 今天录入、但账算在更早的日期；'
                      '紫色「临时调价」= 这一笔的单价与档案不同（档案没被改）。',
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const MutedText(
                      '点任意一条（不要点右侧按钮）可以看精确到秒的录入时间。',
                      align: TextAlign.center,
                    ),
                  ],
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

  Widget _buildSummary(ThemeData theme, String today) {
    final settled = _settledCents;
    final unsettled = _unsettledCents;
    final backfill = _backfillCount;
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
          // 补录笔数单独拎出来：对账时最容易被质疑的就是这几笔
          if (backfill > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const BackfillBadge(compact: true),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '本区间有 $backfill 笔是今天补录的（下方红色高亮）',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statusBox(
                  '未结算',
                  unsettled,
                  AppTheme.warning,
                  Icons.schedule,
                  count: _entries.length - _settledCount,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statusBox(
                  '已结算',
                  settled,
                  AppTheme.success,
                  Icons.check_circle_outline,
                  count: _settledCount,
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

  Widget _statusBox(
    String label,
    int cents,
    Color color,
    IconData icon, {
    required int count,
  }) {
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
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$count 笔',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted),
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
    String today,
  ) {
    final dayTotal = _sum(entries);
    final weekday = Dates.weekdayLabel(date);
    final holiday = CnHolidays.of(date);
    final backfillCount = entries.where((entry) => entry.isBackfill(today)).length;

    return SectionCard(
      titleWidget: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            weekday.isEmpty ? date : '$date $weekday',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (holiday != null) HolidayBadge(holiday, compact: true),
          if (backfillCount > 0) const BackfillBadge(compact: true),
        ],
      ),
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
            _buildEntryRow(theme, entries[index], today),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryRow(ThemeData theme, _DetailEntry entry, String today) {
    final backfill = entry.isBackfill(today);
    final amountColor = entry.isPiece
        ? AppTheme.primary
        : (entry.signedCents >= 0 ? AppTheme.success : AppTheme.danger);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            entry.timeLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: backfill ? AppTheme.danger : AppTheme.muted,
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
                  if (entry.tempPrice) const TempPriceBadge(compact: true),
                  if (backfill)
                    BackfillBadge(
                      daysEarlier: entry.daysEarlier(today),
                      compact: true,
                    ),
                  Text(
                    entry.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: backfill ? AppTheme.danger : null,
                    ),
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
                  if (backfill)
                    Text(
                      '录入 ${Dates.shortMillis(entry.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // 右侧：金额 + 逐笔结算按钮。限宽 + 缩放，金额位数多也不会挤掉左边的文字
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 116),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
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
              const SizedBox(height: 2),
              _buildSettleButton(entry),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // 点一条看「什么时候录的」：业务日期与录入时间摊开给人看
        onTap: () => showRecordTimeSheet(
          context,
          title: entry.isPiece ? '计件时间详情' : '调整项时间详情',
          workDate: entry.date,
          minuteOfDay: entry.minuteOfDay,
          createdAt: entry.createdAt,
          remark: entry.remark,
          workerName: widget.workerName,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.fromLTRB(backfill ? 8 : 0, 4, 0, 4),
          decoration: backfill
              ? BoxDecoration(
                  // 只有左边框 + 浅红底：够醒目，又不会把整页刷成红色
                  color: AppTheme.danger.withValues(alpha: 0.05),
                  border: const Border(
                    left: BorderSide(color: AppTheme.danger, width: 3),
                  ),
                )
              : null,
          child: row,
        ),
      ),
    );
  }

  /// 单笔结算按钮：未结算显示「结算」，已结算显示「取消」。
  Widget _buildSettleButton(_DetailEntry entry) {
    final color = entry.settled ? AppTheme.muted : AppTheme.success;
    return InkWell(
      onTap: _busy ? null : () => _toggleSettled(entry),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              entry.settled ? Icons.undo : Icons.check_circle_outline,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              entry.settled ? '取消' : '结算',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
