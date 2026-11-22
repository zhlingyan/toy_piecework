import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/settlement.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../common/search_field.dart';
import '../common/ui_kit.dart';
import '../count/adjustment_sheet.dart';
import '../theme.dart';
import 'cancel_reason_dialog.dart';
import 'worker_detail_sheet.dart';
import 'worker_records_page.dart';

/// 结算页的两种下钻（全员视角）。
///
/// 「按工人结算」列表回答的是"某一个人的账单是什么样"；
/// 下面两个弹层回答的是"按某个维度筛出全员中涉及的人"：
/// * [showSettlementPeopleSheet]：还有谁没结 / 谁已经结了，可**就地结算**；
/// * [showSettlementCategorySheet]：谁有扣款、谁有补贴（含计时 / 预支 / 计件），
///   可展开看逐笔、可单笔结算、可跳去逐条明细。
///
/// 两者操作后都会立刻重算并刷新，页面上的汇总数字随之变化，不需要退出重进。

/// 按结算状态横切全员：未结算 / 已结算。
Future<void> showSettlementPeopleSheet({
  required BuildContext context,
  required AppServices services,
  required DateRange range,
  required SettlementStatus status,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PeopleDrillSheet(
      services: services,
      range: range,
      status: status,
    ),
  );
}

/// 按项目横切全员：计件 / 补贴 / 计时 / 扣款 / 预支（[type] 为 null 表示计件）。
Future<void> showSettlementCategorySheet({
  required BuildContext context,
  required AppServices services,
  required DateRange range,
  AdjustmentType? type,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CategoryDrillSheet(
      services: services,
      range: range,
      type: type,
    ),
  );
}

String _prettyMonths(Iterable<String> months) => months
    .map((month) => '${month.substring(0, 4)}年${int.parse(month.substring(5, 7))}月')
    .join('、');

/// 弹层通用外壳：把手 + 标题 + 副标题 + 关闭。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFD5D9E0),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 一、未结算 / 已结算：全员名单 + 就地结算
// ---------------------------------------------------------------------------

class _PeopleDrillSheet extends StatefulWidget {
  const _PeopleDrillSheet({
    required this.services,
    required this.range,
    required this.status,
  });

  final AppServices services;
  final DateRange range;
  final SettlementStatus status;

  @override
  State<_PeopleDrillSheet> createState() => _PeopleDrillSheetState();
}

class _PeopleDrillSheetState extends State<_PeopleDrillSheet> {
  final TextEditingController _search = TextEditingController();

  SettlementResult? _result;
  bool _loading = true;

  /// 正在提交的工人 id（防连点，也给按钮一个"处理中"态）。
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _unsettled => widget.status != SettlementStatus.settled;

  Future<void> _load() async {
    final result = await widget.services.settlements.settle(widget.range);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  /// 这个视角下的人：未结算含「部分已结」（还欠着钱的人必须出现）。
  List<WorkerSettlement> get _people {
    final result = _result;
    if (result == null) return const [];
    final query = _search.text.trim();
    final base = result.filterBy(
      _unsettled ? SettlementStatus.unsettled : SettlementStatus.settled,
    );
    if (query.isEmpty) return base;
    return base
        .where(
          (worker) => PinyinHelper.matches(
            query: query,
            name: worker.workerName,
            initials: PinyinHelper.initialsOf(worker.workerName),
            code: worker.workerCode,
          ),
        )
        .toList(growable: false);
  }

  int get _totalCents => _people.fold(
        0,
        (sum, worker) =>
            sum + (_unsettled ? worker.unsettledCents : worker.settledCents),
      );

  Future<void> _markWorker(WorkerSettlement worker, {required bool settled}) async {
    if (_busyId != null) return;
    final months = worker.activeMonths;
    if (months.isEmpty) {
      showToast(context, '「${worker.workerName}」本期没有可结算的账目', isError: true);
      return;
    }
    String? reason;
    if (settled) {
      final ok = await showConfirmDialog(
        context,
        title: '把「${worker.workerName}」本期标记为已结算？',
        message: '覆盖 ${months.length} 个月（${_prettyMonths(months)}），'
            '共 ${worker.recordCount} 笔、应付 ${Money.formatCents(worker.netCents)} 元。\n'
            '只改结算状态，不改任何金额；之后补录的账也会算作已结算。',
        confirmText: '标记已结算',
      );
      if (!ok) return;
    } else {
      // 全员名单里取消结算同样走「理由选填」框，留空照常完成。
      reason = await showCancelSettlementDialog(
        context,
        title: '取消「${worker.workerName}」的结算标记？',
        message: '取消后这 ${months.length} 个月会重新算作未结算（含已单独标记的笔）。\n'
            '金额不变，随时可以再标回来。\n'
            '取消理由选填，留空也能完成。',
      );
      if (reason == null) return;
    }
    setState(() => _busyId = worker.workerId);
    try {
      await widget.services.settlementEntries.markRange(
        workerId: worker.workerId,
        months: months,
        range: widget.range,
        settled: settled,
        reason: reason,
      );
      widget.services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(
        context,
        settled
            ? '已标记「${worker.workerName}」为已结算'
            : '已取消「${worker.workerName}」的结算标记',
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openDetail(WorkerSettlement worker) async {
    await showWorkerDetailSheet(
      context: context,
      services: widget.services,
      worker: worker,
      range: widget.range,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    final query = _search.text.trim();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(
        children: [
          _SheetHeader(
            title: _unsettled ? '未结算 · 全员' : '已结算 · 全员',
            subtitle: '${widget.range.label} · 点工人可看完整账单，'
                '右侧可直接${_unsettled ? '结清' : '取消结算'}',
            onClose: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SearchField(
              controller: _search,
              hintText: '查找：输入工人姓名或工号',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchMatchHint(
                query: query,
                text: '匹配到 ${people.length} 人',
                onClear: () {
                  _search.clear();
                  setState(() {});
                },
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : people.isEmpty
                    ? EmptyState(
                        title: query.isEmpty
                            ? (_unsettled ? '这个区间都已结清' : '还没有人标记已结算')
                            : '没有匹配的工人',
                        hint: query.isEmpty
                            ? (_unsettled
                                ? '所有人的账都结清了，可以去「已结算」核对'
                                : '在工人明细里点「标记本期已结算」后会出现在这里')
                            : '换个姓名或工号试试，或清空查找',
                        icon: query.isEmpty
                            ? Icons.task_alt
                            : Icons.search_off,
                        action: query.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                child: const Text('清空查找'),
                              ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: people.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildSummary(theme, people);
                          }
                          final worker = people[index - 1];
                          return _buildPersonRow(theme, worker);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(ThemeData theme, List<WorkerSettlement> people) {
    final color = _unsettled ? AppTheme.warning : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${people.length} 人',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
            Text(
              '${_unsettled ? '未结' : '已结'} ${Money.formatCents(_totalCents)} 元',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            Text(
              '合计应付 ${Money.formatCents(_result?.totalNetCents ?? 0)} 元',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonRow(ThemeData theme, WorkerSettlement worker) {
    final busy = _busyId == worker.workerId;
    final settled = worker.isFullySettled;
    final amount = _unsettled ? worker.unsettledCents : worker.settledCents;
    final color = _unsettled ? AppTheme.warning : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('drill-person-${worker.workerId}'),
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: busy ? null : () => _openDetail(worker),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E9EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        worker.workerName.isEmpty
                            ? '?'
                            : worker.workerName.characters.first,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                worker.workerName,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              SettlementBadge(worker.settlementStatus,
                                  compact: true),
                              if (worker.isArchived)
                                Text(
                                  '已停用',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.muted),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${worker.workerCode.isEmpty ? '' : '编号 ${worker.workerCode} · '}'
                            '${worker.settledCount}/${worker.recordCount} 笔已结',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              Money.formatCents(amount),
                              maxLines: 1,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            _unsettled ? '未结' : '已结',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 就地操作：不跳进详情也能把这一期结掉
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settled
                            ? (worker.isNegative
                                ? '本期已结清 · 应付为负数，请核对'
                                : '本期已结清')
                            : '未结 ${Money.formatCents(worker.unsettledCents)} 元 · '
                                '${worker.unsettledCount} 笔',
                        maxLines: 2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: settled ? AppTheme.success : AppTheme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      _unsettled
                          ? FilledButton.tonalIcon(
                              onPressed: () => _markWorker(worker, settled: true),
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text('结清本期'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  _markWorker(worker, settled: false),
                              icon: const Icon(Icons.undo, size: 18),
                              label: const Text('取消结算'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 二、计件 / 补贴 / 计时 / 扣款 / 预支：全员按项目下钻
// ---------------------------------------------------------------------------

class _DrillEntry {
  const _DrillEntry({
    required this.id,
    required this.isPiece,
    required this.date,
    required this.minuteOfDay,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    required this.signedCents,
    required this.settled,
    this.adjustment,
  });

  final String id;
  final bool isPiece;
  final String date;
  final int minuteOfDay;
  final int createdAt;
  final String title;
  final String subtitle;
  final int signedCents;
  final bool settled;

  /// 调整项原始对象：可点开编辑 / 删除。
  final Adjustment? adjustment;

  String get timeLabel => Dates.hhmm(minuteOfDay);
}

class _WorkerGroup {
  _WorkerGroup({
    required this.workerId,
    required this.name,
    required this.code,
    required this.entries,
  });

  final String workerId;
  final String name;
  final String code;
  final List<_DrillEntry> entries;

  int get total => entries.fold(0, (sum, entry) => sum + entry.signedCents);

  int get settledCount => entries.where((entry) => entry.settled).length;

  bool get allSettled => entries.isNotEmpty && settledCount == entries.length;
}

class _CategoryDrillSheet extends StatefulWidget {
  const _CategoryDrillSheet({
    required this.services,
    required this.range,
    required this.type,
  });

  final AppServices services;
  final DateRange range;

  /// null = 计件。
  final AdjustmentType? type;

  @override
  State<_CategoryDrillSheet> createState() => _CategoryDrillSheetState();
}

class _CategoryDrillSheetState extends State<_CategoryDrillSheet> {
  final TextEditingController _search = TextEditingController();

  List<_WorkerGroup> _groups = const [];
  bool _loading = true;
  String? _busyKey;

  /// 展开的工人（默认收起：先看"谁有这一项"，再点开看"具体哪几笔"）。
  final Set<String> _expanded = <String>{};

  String get _label => widget.type?.label ?? '计件';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = widget.services;
    final range = widget.range;
    // 一次结算聚合：拿姓名 / 工号 / 整月结算标记，避免每人再查一遍
    final result = await services.settlements.settle(range);
    final info = <String, WorkerSettlement>{
      for (final worker in result.workers) worker.workerId: worker,
    };

    final entries = <String, List<_DrillEntry>>{};
    final fallbackNames = <String, String>{};

    if (widget.type == null) {
      final records = await services.records.listRange(range);
      for (final record in records) {
        fallbackNames[record.workerId] = record.workerNameSnapshot;
        final settledMonths =
            info[record.workerId]?.settledMonths ?? const <String>{};
        entries.putIfAbsent(record.workerId, () => []).add(
              _DrillEntry(
                id: record.id,
                isPiece: true,
                date: record.workDate,
                minuteOfDay: record.minuteOfDay,
                createdAt: record.createdAt,
                title: record.processSnapshot == Defaults.defaultProcess
                    ? record.toyNameSnapshot
                    : '${record.toyNameSnapshot} / ${record.processSnapshot}',
                subtitle: '${record.quantity} 件 × ${record.pricingPriceLabel}'
                    '${record.remark.isEmpty ? '' : ' · ${record.remark}'}',
                signedCents: record.subtotalCents,
                settled: record.isSettled(settledMonths),
              ),
            );
      }
    } else {
      final type = widget.type!;
      final adjustments = await services.adjustments.listRange(range);
      for (final adjustment in adjustments) {
        if (adjustment.type != type) continue;
        fallbackNames[adjustment.workerId] = adjustment.workerNameSnapshot;
        final settledMonths =
            info[adjustment.workerId]?.settledMonths ?? const <String>{};
        entries.putIfAbsent(adjustment.workerId, () => []).add(
              _DrillEntry(
                id: adjustment.id,
                isPiece: false,
                date: adjustment.workDate,
                minuteOfDay: adjustment.minuteOfDay,
                createdAt: adjustment.createdAt,
                title: adjustment.summaryLabel.isEmpty
                    ? type.label
                    : adjustment.summaryLabel,
                subtitle: '',
                signedCents: adjustment.signedCents,
                settled: adjustment.isSettled(settledMonths),
                adjustment: adjustment,
              ),
            );
      }
    }

    final groups = <_WorkerGroup>[];
    for (final entry in entries.entries) {
      final worker = info[entry.key];
      final list = entry.value
        ..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          if (byDate != 0) return byDate;
          return b.minuteOfDay.compareTo(a.minuteOfDay);
        });
      groups.add(
        _WorkerGroup(
          workerId: entry.key,
          name: worker?.workerName ?? fallbackNames[entry.key] ?? '（未知工人）',
          code: worker?.workerCode ?? '',
          entries: list,
        ),
      );
    }
    groups.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      return a.name.compareTo(b.name);
    });

    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  List<_WorkerGroup> get _visible {
    final query = _search.text.trim();
    if (query.isEmpty) return _groups;
    return _groups
        .where(
          (group) => PinyinHelper.matches(
            query: query,
            name: group.name,
            initials: PinyinHelper.initialsOf(group.name),
            code: group.code,
          ),
        )
        .toList(growable: false);
  }

  int get _totalCents => _visible.fold(0, (sum, group) => sum + group.total);

  int get _totalCount =>
      _visible.fold(0, (sum, group) => sum + group.entries.length);

  /// 单笔结算 / 取消。走 [SettlementEntryRepository]，整月已标时会自动展开。
  Future<void> _toggleEntry(_DrillEntry entry, bool settled) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = entry.id);
    try {
      if (entry.isPiece) {
        await widget.services.settlementEntries
            .setRecordSettled(entry.id, settled: settled);
      } else {
        await widget.services.settlementEntries
            .setAdjustmentSettled(entry.id, settled: settled);
      }
      widget.services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(context, settled ? '已标记这一笔为已结算' : '已取消这一笔的结算标记');
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// 把某个工人这一项目的所有笔一起结清 / 取消（只动这一项，不碰别的账）。
  Future<void> _toggleGroup(_WorkerGroup group, bool settled) async {
    if (_busyKey != null) return;
    final targets =
        group.entries.where((entry) => entry.settled != settled).toList();
    if (targets.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: settled
          ? '把这 ${targets.length} 笔$_label 标记为已结算？'
          : '取消这 ${targets.length} 笔$_label 的结算？',
      message: settled
          ? '只影响「${group.name}」名下的$_label，其它计件与调整项不变。\n'
              '合计 ${Money.formatCents(group.total)} 元。'
          : '取消后这些笔会重新算作未结算，金额不变，随时可以再标回来。',
      confirmText: settled ? '标记已结算' : '取消标记',
      danger: !settled,
    );
    if (!ok) return;
    setState(() => _busyKey = 'group:${group.workerId}');
    try {
      for (final entry in targets) {
        if (entry.isPiece) {
          await widget.services.settlementEntries
              .setRecordSettled(entry.id, settled: settled);
        } else {
          await widget.services.settlementEntries
              .setAdjustmentSettled(entry.id, settled: settled);
        }
      }
      widget.services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(
        context,
        settled
            ? '已标记 ${targets.length} 笔$_label 为已结算'
            : '已取消 ${targets.length} 笔$_label 的结算',
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// 跳去某个工人的逐条明细（"看某人完整账单"的入口）。
  Future<void> _openRecords(_WorkerGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerRecordsPage(
          workerId: group.workerId,
          workerName: group.name,
          workerCode: group.code,
          range: widget.range,
        ),
      ),
    );
    if (!mounted) return;
    // 明细页里可能改过结算状态，重算一遍并让结算页同步
    await _load();
    widget.services.notifyDataChanged();
  }

  /// 补录一笔同类调整项（计件不提供：计数页才是录入入口）。
  Future<void> _addEntry() async {
    final type = widget.type;
    if (type == null) return;
    final workers = await widget.services.workers.listAll();
    if (!mounted) return;
    if (workers.isEmpty) {
      showToast(context, '还没有工人档案，请先建档', isError: true);
      return;
    }
    final today = Dates.ymd(AppClock.now());
    final saved = await showAdjustmentSheet(
      context: context,
      services: widget.services,
      defaultDate: widget.range.contains(today) ? today : widget.range.end,
      workers: workers,
      initialType: type,
    );
    if (saved == true) {
      widget.services.notifyDataChanged();
      await _load();
    }
  }

  Future<void> _editEntry(_DrillEntry entry) async {
    final adjustment = entry.adjustment;
    if (adjustment == null) {
      // 计件改单要去计数页（那里有完整的工序/单价逻辑），这里只提示
      showToast(context, '计件明细请到「计数」页当天流水里改');
      return;
    }
    final workers = await widget.services.workers.listAll();
    if (!mounted) return;
    final saved = await showAdjustmentSheet(
      context: context,
      services: widget.services,
      defaultDate: adjustment.date,
      workers: workers,
      existing: adjustment,
    );
    if (saved == true) {
      widget.services.notifyDataChanged();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _visible;
    final query = _search.text.trim();
    final color = widget.type == null || (widget.type?.isPositive ?? true)
        ? AppTheme.success
        : AppTheme.danger;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(
        children: [
          _SheetHeader(
            title: '$_label · 全员',
            subtitle: '${widget.range.label} · 谁有$_label、各多少、哪几笔还没结',
            onClose: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SearchField(
              controller: _search,
              hintText: '查找：输入工人姓名或工号',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchMatchHint(
                query: query,
                text: '匹配到 ${groups.length} 人',
                onClear: () {
                  _search.clear();
                  setState(() {});
                },
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : groups.isEmpty
                    ? EmptyState(
                        title: query.isEmpty ? '这个区间没有$_label' : '没有匹配的工人',
                        hint: query.isEmpty
                            ? (widget.type == null
                                ? '先去「计数」页记几笔'
                                : '点下方「补录一笔」可以现在记一条')
                            : '换个姓名或工号试试，或清空查找',
                        icon: query.isEmpty
                            ? Icons.receipt_long_outlined
                            : Icons.search_off,
                        action: widget.type == null
                            ? null
                            : FilledButton.tonalIcon(
                                onPressed: _addEntry,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text('补录一笔$_label'),
                              ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        itemCount: groups.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildSummary(theme, color);
                          }
                          return _buildGroupCard(theme, groups[index - 1], color);
                        },
                      ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.type != null)
                    OutlinedButton.icon(
                      onPressed: _addEntry,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('补录一笔$_label'),
                    ),
                  const SizedBox(height: 6),
                  const MutedText(
                    '两种视角分工：「按工人结算」看某一个人的完整账单；'
                    '这里是按项目横切，谁有这一项一目了然。',
                    align: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(ThemeData theme, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${_visible.length} 人',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
            Text(
              '合计 ${Money.formatCents(_totalCents)} 元 · $_totalCount 笔',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(ThemeData theme, _WorkerGroup group, Color accent) {
    final expanded = _expanded.contains(group.workerId);
    final busy = _busyKey == 'group:${group.workerId}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('drill-group-${group.workerId}'),
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expanded
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : const Color(0xFFE6E9EF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  if (expanded) {
                    _expanded.remove(group.workerId);
                  } else {
                    _expanded.add(group.workerId);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  group.name,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (group.code.isNotEmpty)
                                  Text(
                                    '编号 ${group.code}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: AppTheme.muted),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${group.entries.length} 笔 · '
                              '已结 ${group.settledCount} 笔',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            Money.formatCentsSigned(group.total),
                            maxLines: 1,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
                  child: Column(
                    children: [
                      for (var index = 0;
                          index < group.entries.length;
                          index++) ...[
                        if (index > 0) const Divider(height: 14),
                        _buildEntryRow(theme, group.entries[index], accent),
                      ],
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openRecords(group),
                            icon: const Icon(Icons.format_list_bulleted, size: 18),
                            label: const Text('完整明细'),
                          ),
                          const Spacer(),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else
                            TextButton.icon(
                              onPressed: () => _toggleGroup(
                                group,
                                !group.allSettled,
                              ),
                              icon: Icon(
                                group.allSettled
                                    ? Icons.undo
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                group.allSettled ? '全部取消' : '全部结清',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryRow(ThemeData theme, _DrillEntry entry, Color accent) {
    final busy = _busyKey == entry.id;
    return InkWell(
      onTap: busy ? null : () => _editEntry(entry),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  if (entry.subtitle.isNotEmpty)
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${entry.date} ${entry.timeLabel}',
                        style: theme.textTheme.bodySmall
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 104),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      Money.formatCentsSigned(entry.signedCents),
                      maxLines: 1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    InkWell(
                      key: ValueKey('drill-entry-settle-${entry.id}'),
                      onTap: () => _toggleEntry(entry, !entry.settled),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          entry.settled ? '取消' : '结算',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: entry.settled
                                ? AppTheme.muted
                                : AppTheme.success,
                          ),
                        ),
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
