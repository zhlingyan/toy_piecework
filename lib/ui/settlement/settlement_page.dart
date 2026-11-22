import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/settlement.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import '../../domain/rules/date_periods.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../../state/selection_state.dart';
import '../common/export_sheet.dart';
import '../common/range_picker_sheet.dart';
import '../common/search_field.dart';
import '../common/ui_kit.dart';
import '../count/adjustment_sheet.dart';
import '../reports/annual_page.dart';
import '../theme.dart';
import '../trash/trash_page.dart';
import 'drill_sheets.dart';
import 'worker_detail_sheet.dart';

/// 结算页：多维区间 + 月度锁账 + 按工人应付。
class SettlementPage extends StatefulWidget {
  const SettlementPage({super.key, required this.selection});

  final SelectionState selection;

  @override
  State<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends State<SettlementPage> {
  late DateRange _range;
  SettlementResult? _result;
  Set<String> _lockedMonths = const {};
  bool _loading = true;
  int _loadedVersion = -1;

  /// 结算状态筛选：null = 全部。
  SettlementStatus? _statusFilter;

  /// 按工人结算的查找框：姓名 / 工号 / 拼音首字母。
  final TextEditingController _workerSearch = TextEditingController();

  /// 「应付合计」是否展开明细（合计 / 已结 / 未结 三个核心指标折叠态也保留）。
  bool _summaryExpanded = true;

  /// 「月度锁账」是否展开。
  ///
  /// null 表示还没手动调过 → 按区间长度自动决定：
  /// 一年 12 个月码成一片圆片太长，默认收起只报"已锁/未锁几个月"。
  bool? _locksExpanded;

  @override
  void initState() {
    super.initState();
    _range = DatePeriods.defaultRange(AppClock.now());
  }

  @override
  void dispose() {
    _workerSearch.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (_loadedVersion != services.refresh.version) {
      _loadedVersion = services.refresh.version;
      _load();
    }
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    if (mounted) setState(() => _loading = true);
    final result = await services.settlements.settle(_range);
    final locked = await services.months.lockedMonths();
    if (!mounted) return;
    setState(() {
      _result = result;
      _lockedMonths = locked;
      _loading = false;
    });
  }

  /// 当前筛选（状态 + 查找）下要展示的工人。
  List<WorkerSettlement> get _visibleWorkers {
    final result = _result;
    if (result == null) return const [];
    final query = _workerSearch.text.trim();
    final byStatus = result.filterBy(_statusFilter);
    if (query.isEmpty) return byStatus;
    return byStatus
        .where((worker) => _matchesWorker(worker, query))
        .toList(growable: false);
  }

  /// 姓名 / 工号 / 首字母任一命中。
  bool _matchesWorker(WorkerSettlement worker, String query) {
    if (query.isEmpty) return true;
    return PinyinHelper.matches(
      query: query,
      name: worker.workerName,
      initials: PinyinHelper.initialsOf(worker.workerName),
      code: worker.workerCode,
    );
  }

  String get _workerQuery => _workerSearch.text.trim();

  void _clearWorkerSearch() {
    _workerSearch.clear();
    setState(() {});
  }

  /// 切换区间：锁账折叠状态按新区间重新自动判定。
  void _applyRange(DateRange range) {
    setState(() {
      _range = range;
      _locksExpanded = null;
    });
    _load();
  }

  /// 点开区间入口：弹出完整区间列表，选中立刻生效。
  Future<void> _openRangePicker() async {
    final pick = await showRangePickerSheet(
      context: context,
      current: _range,
      now: AppClock.now(),
    );
    if (pick == null || !mounted) return;
    if (pick.custom) {
      await _pickCustomRange();
      return;
    }
    _applyRange(pick.range);
  }

  Future<void> _pickCustomRange() async {
    final now = AppClock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: DateTime.parse(_range.start),
        end: DateTime.parse(_range.end),
      ),
      helpText: '选择结算区间',
      saveText: '确定',
      fieldStartLabelText: '开始日期',
      fieldEndLabelText: '结束日期',
    );
    if (picked == null) return;
    _applyRange(DateRange.of(Dates.ymd(picked.start), Dates.ymd(picked.end)));
  }

  Future<void> _toggleLock(String month) async {
    final services = AppScope.of(context);
    final isLocked = _lockedMonths.contains(month);
    final pretty = '${month.substring(0, 4)}年${int.parse(month.substring(5, 7))}月';
    if (isLocked) {
      final ok = await showConfirmDialog(
        context,
        title: '解锁 $pretty？',
        message: '解锁后该月可以继续修改、补录和删除。'
            '如果已经和工人结清工资，请确认账目确实需要调整。',
        confirmText: '确认解锁',
        danger: true,
      );
      if (!ok) return;
      await services.months.unlock(month);
      if (!mounted) return;
      showToast(context, '$pretty 已解锁');
    } else {
      final ok = await showConfirmDialog(
        context,
        title: '锁定 $pretty？',
        message: '锁账后该月的计件与调整项将不能新增、修改、删除，'
            '回收站也不能恢复该月记录。仍可查看、导出与备份。',
        confirmText: '确认锁账',
      );
      if (!ok) return;
      await services.months.lock(month);
      if (!mounted) return;
      showToast(context, '$pretty 已锁账');
    }
    services.notifyDataChanged();
    await _load();
  }

  Future<void> _openWorkerDetail(WorkerSettlement worker) async {
    final services = AppScope.of(context);
    await showWorkerDetailSheet(
      context: context,
      services: services,
      worker: worker,
      range: _range,
    );
    await _load();
  }

  /// 点「未结算 / 已结算」：横向筛出全员名单，可就地结算 / 取消结算。
  ///
  /// 与「按工人结算」列表的区别是视角：那边是"从人找到账"，
  /// 这里是"从状态找到人"——月底最常问的是"还有谁没发钱"。
  Future<void> _openPeopleDrill(SettlementStatus status) async {
    final result = _result;
    if (result == null) return;
    final target = status == SettlementStatus.unsettled
        ? result.unsettledWorkerCount
        : result.settledWorkerCount;
    if (target == 0) {
      showToast(
        context,
        status == SettlementStatus.unsettled ? '这个区间所有人都已结清' : '这个区间还没有已结算的账',
      );
      return;
    }
    await showSettlementPeopleSheet(
      context: context,
      services: AppScope.read(context),
      range: _range,
      status: status,
    );
    if (!mounted) return;
    await _load();
  }

  /// 点「计件 / 补贴 / 计时 / 扣款 / 预支」：按项目横向看全员。
  ///
  /// [type] 为 null 表示计件。
  Future<void> _openCategoryDrill(AdjustmentType? type) async {
    final result = _result;
    if (result == null) return;
    final label = type?.label ?? '计件';
    final hasAny = type == null
        ? result.workers.any((worker) => worker.groups.isNotEmpty)
        : result.workers.any(
            (worker) => (worker.adjustmentTotals[type] ?? 0) > 0,
          );
    if (!hasAny) {
      showToast(context, '这个区间没有$label');
      return;
    }
    await showSettlementCategorySheet(
      context: context,
      services: AppScope.read(context),
      range: _range,
      type: type,
    );
    if (!mounted) return;
    await _load();
  }

  /// 导出当前区间的结算表：一人一行 + 合计行，Excel 直接打开不乱码。
  /// 从结算页直接记一笔补贴 / 扣款，不用先点进某个工人。
  Future<void> _addAdjustment() async {
    final services = AppScope.read(context);
    final workers = await services.workers.listActive();
    if (!mounted) return;
    if (workers.isEmpty) {
      showToast(context, '还没有工人档案，请先建档', isError: true);
      return;
    }
    // 默认日期必须落在**当前区间内**：在"上个月"里补录补贴，
    // 落到今天就会看不见（钱记到了下个月），这是最容易引起对账争议的坑。
    final saved = await showAdjustmentSheet(
      context: context,
      services: services,
      defaultDate: _defaultAdjustmentDate(),
      workers: workers,
    );
    if (saved == true) {
      services.notifyDataChanged();
      _load();
    }
  }

  /// 补录调整项的默认日期：今天在当前区间内就用今天，否则用区间最后一天。
  String _defaultAdjustmentDate() {
    final today = Dates.ymd(AppClock.now());
    return _range.contains(today) ? today : _range.end;
  }

  Future<void> _exportCsv() async {
    final result = _result;
    if (result == null || result.workers.isEmpty) {
      showToast(context, '当前区间没有可导出的结算数据', isError: true);
      return;
    }
    final services = AppScope.read(context);
    final csv = services.csv.settlementCsv(result);
    final range = _range;
    await showCsvExportSheet(
      context,
      csv: csv,
      fileName: '结算表-${range.start}_${range.end}.csv',
      title: '导出 ${range.label} 结算表',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final months = _range.months;

    return Scaffold(
      appBar: AppBar(
        title: const Text('结算'),
        centerTitle: false,
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '记一笔补贴 / 扣款',
            icon: const Icon(Icons.add_card_outlined),
            onPressed: _addAdjustment,
          ),
          IconButton(
            tooltip: '导出 CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _loading ? null : _exportCsv,
          ),
          IconButton(
            tooltip: '年度报表',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AnnualPage()),
            ),
          ),
          IconButton(
            tooltip: '回收站',
            icon: const Icon(Icons.restore_from_trash_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashPage()),
              );
              await _load();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _buildRangeBar(theme),
                  const SizedBox(height: 12),
                  _buildSummaryCard(theme, result),
                  if (months.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildLocksCard(theme, months),
                  ],
                  SectionCard(
                    title: '按工人结算',
                    trailing: Text(
                      '${_visibleWorkers.length}/${result?.workers.length ?? 0} 人',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    child: (result == null || result.workers.isEmpty)
                        ? const EmptyState(
                            title: '这个区间还没有数据',
                            hint: '换个区间，或先去「计数」页记几笔',
                            icon: Icons.receipt_long_outlined,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStatusFilter(theme, result),
                              const SizedBox(height: 8),
                              SearchField(
                                key: const ValueKey('settlement-worker-search'),
                                controller: _workerSearch,
                                hintText: '查找：输入工人姓名或工号',
                                onChanged: (_) => setState(() {}),
                              ),
                              if (_workerQuery.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SearchMatchHint(
                                  query: _workerQuery,
                                  text: '匹配到 ${_visibleWorkers.length}/'
                                      '${result.filterBy(_statusFilter).length} 人',
                                  onClear: _clearWorkerSearch,
                                ),
                              ],
                              const SizedBox(height: 6),
                              if (_visibleWorkers.isEmpty)
                                _buildWorkerEmptyState(result)
                              else
                                for (var index = 0;
                                    index < _visibleWorkers.length;
                                    index++) ...[
                                  if (index > 0) const Divider(height: 18),
                                  _buildWorkerRow(
                                    theme,
                                    _visibleWorkers[index],
                                  ),
                                ],
                            ],
                          ),
                  ),
                  if (result != null && result.workers.isNotEmpty) ...[
                    Center(
                      child: MutedText(
                        '报表口径：逐笔取整后合计（每笔小计先四舍五入到分，再累加）',
                        align: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// 区间入口：一个卡片，点开是完整列表（周 / 月 / 季度 / 半年 / 年 + 自定义）。
  ///
  /// 平铺十几个小圆片既挤又记不住口径，改成入口 + 列表后，
  /// 每一项都能在选中前看到起止日期。
  Widget _buildRangeBar(ThemeData theme) {
    final matched = DatePeriods.match(_range, AppClock.now());
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openRangePicker,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E4EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          matched?.label ?? '自定义区间',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (matched?.note != null)
                          Text(
                            matched!.note!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppTheme.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_range.label} · ${_range.dayCount} 天',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '切换区间',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// 应付合计：可折叠，折叠态只留「合计 / 已结算 / 未结算」三个核心口径。
  ///
  /// 一年期的明细（计件、补贴、计时、扣款、预支、笔数）加起来能占半屏，
  /// 但真正决定"还要发多少钱"的只有合计与已结/未结两块，所以折叠时保留它们。
  Widget _buildSummaryCard(ThemeData theme, SettlementResult? result) {
    final net = result?.totalNetCents ?? 0;
    final expanded = _summaryExpanded;
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '应付合计',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.muted),
                ),
              ),
              _collapseButton(
                key: const ValueKey('summary-collapse'),
                expanded: expanded,
                onTap: () => setState(() => _summaryExpanded = !expanded),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // 金额位数多 + 超大字号时，宁可等比缩小也不许溢出
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Money.formatCents(net),
                    maxLines: 1,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: net < 0 ? AppTheme.danger : AppTheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('元 · ${result?.workerCount ?? 0} 人',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.muted)),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _miniStat('计件', Money.formatCents(result?.totalPieceCents ?? 0),
                    key: const ValueKey('summary-metric-piece'),
                    onTap: () => _openCategoryDrill(null)),
                _miniStat('补贴', Money.formatCents(result?.bonusTotal ?? 0),
                    key: const ValueKey('summary-metric-bonus'),
                    onTap: () => _openCategoryDrill(AdjustmentType.bonus)),
                _miniStat('计时', Money.formatCents(result?.hourlyTotal ?? 0),
                    key: const ValueKey('summary-metric-hourly'),
                    onTap: () => _openCategoryDrill(AdjustmentType.hourly)),
                _miniStat('扣款', Money.formatCents(result?.deductionTotal ?? 0),
                    key: const ValueKey('summary-metric-deduction'),
                    onTap: () => _openCategoryDrill(AdjustmentType.deduction)),
                _miniStat('预支', Money.formatCents(result?.advanceTotal ?? 0),
                    key: const ValueKey('summary-metric-advance'),
                    onTap: () => _openCategoryDrill(AdjustmentType.advance)),
                _miniStat('笔数', '${result?.recordCount ?? 0}'),
                _miniStat(
                  '已结笔数',
                  '${result?.settledRecordCount ?? 0}/'
                      '${result?.totalRecordCount ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: 6),
            const MutedText(
              '点「计件 / 补贴 / 计时 / 扣款 / 预支」可按项目看全员：'
              '谁有这一项、各多少、哪些还没结。',
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEDEFF3)),
          const SizedBox(height: 10),
          // 已结 / 未结分开显示：一眼看出「还有多少人的钱没发」。
          // 两块都能点开看全员名单，并当场结算 / 取消结算。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _settlementStat(
                  key: const ValueKey('summary-unsettled'),
                  label: '未结算',
                  cents: result?.unsettledTotalCents ?? 0,
                  color: AppTheme.warning,
                  people: result?.unsettledWorkerCount ?? 0,
                  onTap: () => _openPeopleDrill(SettlementStatus.unsettled),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _settlementStat(
                  key: const ValueKey('summary-settled'),
                  label: '已结算',
                  cents: result?.settledTotalCents ?? 0,
                  color: AppTheme.success,
                  people: result?.settledWorkerCount ?? 0,
                  onTap: () => _openPeopleDrill(SettlementStatus.settled),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (expanded)
            const MutedText(
              '结算状态可以按笔记：点工人行进「详细明细」，每一笔右侧都能单独结算/取消；'
              '也可以一次「标记本期已结算」整期勾掉。补贴 / 计时 / 扣款 / 预支的每一笔'
              '同样在那里查看、补录与单独结算。',
            )
          else
            const MutedText('展开可看计件 / 补贴 / 计时 / 扣款 / 预支与结算进度；'
                '点「未结算 / 已结算」可直接看全员名单并结账。'),
        ],
      ),
    );
  }

  /// 折叠 / 展开按钮（文案 + 箭头），两个区块共用。
  Widget _collapseButton({
    Key? key,
    required bool expanded,
    required VoidCallback onTap,
    String expandText = '展开明细',
    String collapseText = '收起明细',
  }) {
    return TextButton.icon(
      key: key,
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        size: 20,
      ),
      label: Text(expanded ? collapseText : expandText),
    );
  }

  /// 月度锁账：可折叠。折叠态只报「已锁 / 未锁几个月」。
  Widget _buildLocksCard(ThemeData theme, List<String> months) {
    final locked = months.where(_lockedMonths.contains).length;
    final unlocked = months.length - locked;
    // null = 用户没手动调过：超过 6 个月（半年 / 全年）默认收起
    final expanded = _locksExpanded ?? months.length <= 6;
    return SectionCard(
      title: '月度锁账',
      trailing: _collapseButton(
        key: const ValueKey('locks-collapse'),
        expanded: expanded,
        onTap: () => setState(() => _locksExpanded = !expanded),
        expandText: '展开 ${months.length} 个月',
        collapseText: '收起',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 折叠态也要能一眼看出"还有几个月没锁"——这是锁账唯一的摘要口径
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _lockSummaryChip(
                icon: Icons.lock,
                color: AppTheme.danger,
                text: '已锁 $locked 个月',
              ),
              _lockSummaryChip(
                icon: Icons.lock_open,
                color: AppTheme.success,
                text: '未锁 $unlocked 个月',
              ),
              if (locked > 0 && unlocked > 0)
                Text(
                  '共 ${months.length} 个月',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.muted),
                ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final month in months) _buildMonthChip(theme, month),
              ],
            ),
            const SizedBox(height: 6),
            const MutedText('点月份可锁定 / 解锁；锁账只防改账，不影响结算标记与导出。'),
          ] else ...[
            const SizedBox(height: 6),
            const MutedText('展开后可逐月锁定 / 解锁。'),
          ],
        ],
      ),
    );
  }

  Widget _lockSummaryChip({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 按工人结算的"没有结果"提示：区分「查找没命中」和「筛选没命中」。
  Widget _buildWorkerEmptyState(SettlementResult result) {
    if (_workerQuery.isNotEmpty) {
      return EmptyState(
        title: '没有匹配的工人',
        hint: '「$_workerQuery」在本区间没有账目。换个姓名或工号，或清空查找。',
        icon: Icons.search_off,
        action: TextButton(
          onPressed: _clearWorkerSearch,
          child: const Text('清空查找'),
        ),
      );
    }
    return EmptyState(
      title: _statusFilter == SettlementStatus.unsettled
          ? '这个区间没有未结算的账'
          : '这个区间没有已结算的账',
      hint: '换一个筛选看看，或在工人明细里标记结算状态',
      icon: Icons.filter_alt_off_outlined,
    );
  }

  /// 结算进度小卡：金额 + 人数，**整块可点**——点开就是全员对应名单。
  ///
  /// 加了 `点开` 提示箭头与"可点"的水波纹，否则用户看不出这块是入口。
  Widget _settlementStat({
    Key? key,
    required String label,
    required int cents,
    required Color color,
    required int people,
    VoidCallback? onTap,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final radius = BorderRadius.circular(12);
        return Material(
          key: key,
          color: color.withValues(alpha: 0.07),
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        label == '已结算'
                            ? Icons.check_circle_outline
                            : Icons.schedule,
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$people 人',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppTheme.muted),
                        ),
                      ),
                      if (onTap != null) ...[
                        const Spacer(),
                        Icon(Icons.chevron_right, size: 18, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
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
                  if (onTap != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '点开看名单',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: color.withValues(alpha: 0.85)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 全部 / 未结算 / 已结算 三个筛选片。
  Widget _buildStatusFilter(ThemeData theme, SettlementResult result) {
    final items = <({SettlementStatus? status, String label, int count})>[
      (status: null, label: '全部', count: result.workers.length),
      (
        status: SettlementStatus.unsettled,
        label: '未结算',
        count: result.unsettledWorkerCount,
      ),
      (
        status: SettlementStatus.settled,
        label: '已结算',
        count: result.settledWorkerCount,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items) ...[
            ChoiceChip(
              label: Text('${item.label} ${item.count}'),
              selected: _statusFilter == item.status,
              onSelected: (_) => setState(() => _statusFilter = item.status),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// 汇总小项。给了 [onTap] 就是可点下钻的入口（带箭头 + 主色数字）。
  Widget _miniStat(String label, String value, {Key? key, VoidCallback? onTap}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: onTap == null ? null : AppTheme.primary,
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppTheme.primary),
          ],
        );
        if (onTap == null) return KeyedSubtree(key: key, child: content);
        return InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildMonthChip(ThemeData theme, String month) {
    final locked = _lockedMonths.contains(month);
    final label = '${month.substring(0, 4)}-${month.substring(5, 7)}';
    return ActionChip(
      avatar: Icon(
        locked ? Icons.lock : Icons.lock_open,
        size: 18,
        color: locked ? AppTheme.danger : AppTheme.success,
      ),
      label: Text(
        locked ? '$label 已锁' : '$label 未锁',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: locked ? AppTheme.danger : AppTheme.success,
        ),
      ),
      onPressed: () => _toggleLock(month),
    );
  }

  Widget _buildWorkerRow(ThemeData theme, WorkerSettlement worker) {
    final net = worker.netCents;
    return InkWell(
      key: ValueKey('settlement-worker-${worker.workerId}'),
      onTap: () => _openWorkerDetail(worker),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: Text(
                worker.workerName.characters.first,
                style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 姓名可能很长（如「张三（临时工）」），
                      // 大字模式下必须允许收缩，否则会把标签挤出屏幕
                      Flexible(
                        child: Text(
                          worker.workerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SettlementBadge(worker.settlementStatus, compact: true),
                      if (worker.isArchived) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDEFF3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('已停用', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        worker.onlyAdjustments
                            ? '仅调整项'
                            : '${worker.groups.length} 项工序 · ${worker.totalQuantity} 件',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.muted),
                      ),
                      if (!worker.isFullySettled && worker.netCents != 0)
                        Text(
                          '未结 ${Money.formatCents(worker.unsettledCents)} 元',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Money.formatCents(net),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: net < 0 ? AppTheme.danger : AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (net < 0)
                  const Text(
                    '负数，请核对',
                    style: TextStyle(fontSize: 12, color: AppTheme.danger),
                  ),
              ],
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
          ],
        ),
      ),
    );
  }
}
