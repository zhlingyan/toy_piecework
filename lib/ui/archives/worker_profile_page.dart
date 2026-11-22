import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../data/models/worker.dart';
import '../../data/services/report_service.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 员工档案：累计数据 + 做过的玩具 + 每日时间线。
///
/// 档案是「查历史」的地方，不做任何写入，因此锁账月份也能正常查看。
class WorkerProfilePage extends StatefulWidget {
  const WorkerProfilePage({super.key, required this.worker});

  final Worker worker;

  @override
  State<WorkerProfilePage> createState() => _WorkerProfilePageState();
}

class _WorkerProfilePageState extends State<WorkerProfilePage> {
  WorkerProfile? _profile;
  bool _loading = true;
  bool _showAllDays = false;

  static const int _dayLimit = 120;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.read(context);
    final profile = await services.reports.profile(
      widget.worker.id,
      dayLimit: _dayLimit,
    );
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worker = widget.worker;
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(worker.name),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop('edit'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _buildHeader(theme, worker, profile),
                  const SizedBox(height: 14),
                  if (profile == null || profile.isEmpty)
                    const EmptyState(
                      title: '还没有计件记录',
                      hint: '等他在「计数」页有了产量，这里就会自动出现统计',
                      icon: Icons.person_search_outlined,
                    )
                  else ...[
                    _buildToys(theme, profile),
                    const SizedBox(height: 14),
                    _buildTimeline(theme, profile),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    Worker worker,
    WorkerProfile? profile,
  ) {
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: worker.isArchived
                    ? const Color(0xFFEDEFF3)
                    : AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  worker.name.characters.first,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: worker.isArchived ? AppTheme.muted : AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          worker.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          worker.code,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      worker.isArchived ? '已停用（历史数据保留）' : '在用',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: worker.isArchived
                            ? AppTheme.muted
                            : AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _mini(
                  theme,
                  label: '累计产量',
                  value: '${profile?.totalQuantity ?? 0}',
                  unit: '件',
                ),
              ),
              Expanded(
                child: _mini(
                  theme,
                  label: '累计工资',
                  value: Money.formatCents(profile?.totalCents ?? 0),
                  unit: '元',
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: const Color(0xFFEDEFF3), height: 1),
          const SizedBox(height: 10),
          KeyValueRow(
            label: '首次记工',
            value: profile?.firstDate ?? '—',
          ),
          KeyValueRow(
            label: '最近记工',
            value: profile?.lastDate ?? '—',
          ),
          KeyValueRow(
            label: '拼音首字母',
            value: worker.pinyinInitials.isEmpty ? '—' : worker.pinyinInitials,
          ),
        ],
      ),
    );
  }

  Widget _mini(
    ThemeData theme, {
    required String label,
    required String value,
    required String unit,
    Color? color,
  }) {
    final accent = color ?? AppTheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToys(ThemeData theme, WorkerProfile profile) {
    return SectionCard(
      title: '做过的玩具',
      trailing: Text(
        '${profile.toys.length} 项',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
      ),
      child: profile.toys.isEmpty
          ? const MutedText('暂无计件记录')
          : Column(
              children: [
                for (var index = 0; index < profile.toys.length; index++) ...[
                  if (index > 0) const Divider(height: 16),
                  _buildToyRow(theme, profile.toys[index]),
                ],
              ],
            ),
    );
  }

  Widget _buildToyRow(ThemeData theme, AnnualLine line) {
    final label = line.process == Defaults.defaultProcess
        ? line.toyName
        : '${line.toyName} / ${line.process}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${line.quantity} 件 · 最近 ${line.lastDate}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.muted),
              ),
            ],
          ),
        ),
        Text(
          Money.formatCents(line.cents),
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildTimeline(ThemeData theme, WorkerProfile profile) {
    final days = _showAllDays ? profile.days : profile.days.take(15).toList();
    final hasMore = profile.days.length > 15;
    return SectionCard(
      title: '每日时间线',
      trailing: Text(
        '最近 ${profile.days.length} 天有记录',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < days.length; index++) ...[
            if (index > 0) const Divider(height: 14),
            _buildDayRow(theme, days[index]),
          ],
          if (hasMore)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => setState(() => _showAllDays = !_showAllDays),
                child: Text(_showAllDays ? '收起' : '展开全部 ${profile.days.length} 天'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayRow(ThemeData theme, WorkerDaySummary day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              day.date,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              day.recordCount == 0
                  ? '仅调整项'
                  : '${day.quantity} 件 · ${day.recordCount} 笔',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.muted),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (day.pieceCents != 0)
                Text(
                  Money.formatCents(day.pieceCents),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              if (day.adjustmentCount > 0)
                Text(
                  '调整 ${Money.formatCentsSigned(day.adjustmentNetCents)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: day.adjustmentNetCents < 0
                        ? AppTheme.danger
                        : AppTheme.success,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
