import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/settlement.dart';
import '../../services/app_services.dart';
import '../../state/selection_state.dart';
import '../common/export_sheet.dart';
import '../common/ui_kit.dart';
import '../reports/annual_page.dart';
import '../theme.dart';
import '../trash/trash_page.dart';
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
  int _rangePreset = 2; // 0 今日 1 近7天 2 本月 3 上月 4 自定义

  @override
  void initState() {
    super.initState();
    _range = DateRange.thisMonth(DateTime.now());
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

  void _applyPreset(int preset) {
    final now = DateTime.now();
    DateRange range;
    switch (preset) {
      case 0:
        range = DateRange.day(now);
      case 1:
        range = DateRange.last7Days(now);
      case 2:
        range = DateRange.thisMonth(now);
      case 3:
        range = DateRange.lastMonth(now);
      default:
        return;
    }
    setState(() {
      _rangePreset = preset;
      _range = range;
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
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
    setState(() {
      _rangePreset = 4;
      _range = DateRange.of(Dates.ymd(picked.start), Dates.ymd(picked.end));
    });
    _load();
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

  /// 导出当前区间的结算表：一人一行 + 合计行，Excel 直接打开不乱码。
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
                    SectionCard(
                      title: '月度锁账',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final month in months)
                            _buildMonthChip(theme, month),
                        ],
                      ),
                    ),
                  ],
                  SectionCard(
                    title: '按工人结算',
                    trailing: Text(
                      '${result?.workers.length ?? 0} 人',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    child: (result == null || result.workers.isEmpty)
                        ? const EmptyState(
                            title: '这个区间还没有数据',
                            hint: '换个区间，或先去「计数」页记几笔',
                            icon: Icons.receipt_long_outlined,
                          )
                        : Column(
                            children: [
                              for (var index = 0;
                                  index < result.workers.length;
                                  index++) ...[
                                if (index > 0) const Divider(height: 18),
                                _buildWorkerRow(theme, result.workers[index]),
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

  Widget _buildRangeBar(ThemeData theme) {
    final presets = ['今日', '近7天', '本月', '上月'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('区间', style: theme.textTheme.titleMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _range.label,
                style: theme.textTheme.bodyLarge?.copyWith(color: AppTheme.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _pickCustomRange,
              icon: const Icon(Icons.date_range, size: 20),
              label: const Text('自定义'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < presets.length; index++) ...[
                ChoiceChip(
                  label: Text(presets[index]),
                  selected: _rangePreset == index,
                  onSelected: (_) => _applyPreset(index),
                ),
                const SizedBox(width: 8),
              ],
              if (_rangePreset == 4)
                const ChoiceChip(label: Text('自定义'), selected: true, onSelected: null),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ThemeData theme, SettlementResult? result) {
    final net = result?.totalNetCents ?? 0;
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('应付合计', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Money.formatCents(net),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: net < 0 ? AppTheme.danger : AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text('元',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _miniStat('计件', Money.formatCents(result?.totalPieceCents ?? 0)),
              _miniStat('补贴', Money.formatCents(result?.bonusTotal ?? 0)),
              _miniStat('计时', Money.formatCents(result?.hourlyTotal ?? 0)),
              _miniStat('扣款', Money.formatCents(result?.deductionTotal ?? 0)),
              _miniStat('预支', Money.formatCents(result?.advanceTotal ?? 0)),
              _miniStat('笔数', '${result?.recordCount ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
            const SizedBox(width: 4),
            Text(value,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
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
                      Text(
                        worker.workerName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
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
                  Text(
                    worker.onlyAdjustments
                        ? '仅调整项'
                        : '${worker.groups.length} 项工序 · ${worker.totalQuantity} 件',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
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
