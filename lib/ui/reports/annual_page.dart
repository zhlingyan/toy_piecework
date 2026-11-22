import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../data/services/report_service.dart';
import '../../services/app_services.dart';
import '../common/export_sheet.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 年度报表：按年统计每人的年产量、年工资，并可按玩具/工序展开。
class AnnualPage extends StatefulWidget {
  const AnnualPage({super.key});

  @override
  State<AnnualPage> createState() => _AnnualPageState();
}

class _AnnualPageState extends State<AnnualPage> {
  int _year = DateTime.now().year;
  AnnualReport? _report;
  bool _loading = true;
  bool _exporting = false;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.read(context);
    setState(() => _loading = true);
    final report = await services.reports.annual(_year);
    if (!mounted) return;
    setState(() {
      _report = report;
      _expanded.clear();
      _loading = false;
    });
  }

  void _changeYear(int delta) {
    final next = _year + delta;
    if (next > DateTime.now().year || next < 2000) return;
    setState(() => _year = next);
    _load();
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null || report.isEmpty || _exporting) return;
    final services = AppScope.read(context);
    setState(() => _exporting = true);
    try {
      final csv = services.csv.annualCsv(
        year: _year,
        rows: [
          for (final worker in report.workers)
            for (final line in worker.lines)
              (
                workerId: worker.workerId,
                workerName: worker.workerName,
                toyName: line.toyName,
                process: line.process,
                quantity: line.quantity,
                cents: line.cents,
              ),
        ],
      );
      if (!mounted) return;
      await showCsvExportSheet(
        context,
        csv: csv,
        fileName: '年度报表-$_year.csv',
        title: '导出 $_year 年度报表',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('年度报表'),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '导出 CSV',
            onPressed: (report == null || report.isEmpty || _exporting)
                ? null
                : _export,
            icon: const Icon(Icons.file_download_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildYearBar(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: report == null || report.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              EmptyState(
                                title: '$_year 年还没有计件记录',
                                hint: '换一个年份看看，或先在「计数」页录入',
                                icon: Icons.bar_chart_outlined,
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            children: [
                              _buildSummary(theme, report),
                              const SizedBox(height: 12),
                              SectionCard(
                                title: '工人明细',
                                trailing: Text(
                                  '${report.workerCount} 人',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: AppTheme.muted),
                                ),
                                child: Column(
                                  children: [
                                    for (var index = 0;
                                        index < report.workers.length;
                                        index++) ...[
                                      if (index > 0) const Divider(height: 18),
                                      _buildWorker(theme, report.workers[index]),
                                    ],
                                  ],
                                ),
                              ),
                              Center(
                                child: MutedText(
                                  '口径：只统计未删除的计件流水，逐笔取整后累加',
                                  align: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _changeYear(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一年',
          ),
          Expanded(
            child: Text(
              '$_year 年',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: _year >= DateTime.now().year ? null : () => _changeYear(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一年',
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(ThemeData theme, AnnualReport report) {
    final top = report.topWorker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatBlock(
                label: '年产量',
                value: '${report.quantity}',
                unit: '件',
                icon: Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatBlock(
                label: '年工资',
                value: Money.formatCents(report.cents),
                unit: '元',
                color: AppTheme.success,
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (top != null)
          InfoBanner(
            icon: Icons.emoji_events_outlined,
            color: AppTheme.success,
            text: '产量最高：${top.workerName}，'
                '${top.quantity} 件 · ${Money.formatCents(top.cents)} 元',
          ),
      ],
    );
  }

  Widget _buildWorker(ThemeData theme, AnnualWorker worker) {
    final expanded = _expanded.contains(worker.workerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              if (expanded) {
                _expanded.remove(worker.workerId);
              } else {
                _expanded.add(worker.workerId);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    worker.workerName.characters.first,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppTheme.primary),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDEFF3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '已停用',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${worker.quantity} 件 · ${worker.lineCount} 项工序',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.formatCents(worker.cents),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      expanded ? '收起' : '展开',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            margin: const EdgeInsets.only(top: 6, left: 6),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final line in worker.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.process == Defaults.defaultProcess
                                    ? line.toyName
                                    : '${line.toyName} / ${line.process}',
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${line.quantity} 件 · 最后 ${line.lastDate}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: AppTheme.muted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Money.formatCents(line.cents),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
