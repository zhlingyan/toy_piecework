import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/settlement.dart';
import '../../data/models/settlement_event.dart';
import '../../data/models/worker.dart';
import '../../domain/rules/backfill_rules.dart';
import '../../domain/rules/price_rules.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../common/export_sheet.dart';
import '../common/ui_kit.dart';
import '../count/adjustment_sheet.dart';
import '../theme.dart';
import 'cancel_reason_dialog.dart';
import 'settlement_history_sheet.dart';
import 'worker_records_page.dart';

/// 单人结算明细：计件分组（按单价拆行）+ 调整项增删改。
Future<void> showWorkerDetailSheet({
  required BuildContext context,
  required AppServices services,
  required WorkerSettlement worker,
  required DateRange range,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _WorkerDetailSheet(
      services: services,
      worker: worker,
      range: range,
    ),
  );
}

class _WorkerDetailSheet extends StatefulWidget {
  const _WorkerDetailSheet({
    required this.services,
    required this.worker,
    required this.range,
  });

  final AppServices services;
  final WorkerSettlement worker;
  final DateRange range;

  @override
  State<_WorkerDetailSheet> createState() => _WorkerDetailSheetState();
}

class _WorkerDetailSheetState extends State<_WorkerDetailSheet> {
  List<Adjustment> _adjustments = const [];

  /// 弹层打开后本地刷新的一份结算结果。
  ///
  /// 不能在整段生命周期里只用外面传进来的快照：标记结算、补录调整项之后，
  /// 状态和金额都会变，用旧快照会出现「按钮点了但金额没动」。
  late WorkerSettlement _worker = widget.worker;

  /// 玩具档案的当前单价：用来判断某行是不是「临时调价」。
  Map<String, int> _basePrices = const {};
  bool _loading = true;
  bool _locked = false;
  bool _buildingPayslip = false;
  bool _marking = false;

  /// 当前状态标识：最近一次变更 + 累计变更次数（历史表只追加，不覆盖）。
  SettlementEvent? _latestEvent;
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adjustments = await widget.services.adjustments.listRange(
      widget.range,
      workerId: widget.worker.workerId,
    );
    final lockedMonths = await widget.services.months.lockedMonths();
    final fresh = await widget.services.settlements.settle(
      widget.range,
      workerId: widget.worker.workerId,
    );
    final toys = await widget.services.toys.listAll();
    final events = await widget.services.settlementHistory
        .listForWorker(widget.worker.workerId, limit: 1);
    final count = await widget.services.settlementHistory
        .countForWorker(widget.worker.workerId);
    if (!mounted) return;
    setState(() {
      _adjustments = adjustments;
      // 该人本期可能一笔都没有（比如刚被删空），此时保留外部快照
      _worker = fresh.workers.isEmpty ? widget.worker : fresh.workers.first;
      _basePrices = {for (final toy in toys) toy.id: toy.unitPriceTenThousandth};
      _locked = widget.range.months.any(lockedMonths.contains);
      _latestEvent = events.isEmpty ? null : events.first;
      _historyCount = count;
      _loading = false;
    });
  }

  /// 本区间内「有账」的月份：结算标记只针对这些月份。
  ///
  /// 把界面上新录入的调整项月份也并进来：弹层打开后补记一笔 7 月的补贴，
  /// 标记时就得把 7 月一起标上，否则关掉再打开会突然变成「部分已结」。
  List<String> get _activeMonths {
    final months = <String>{
      ..._worker.monthNetCents.keys,
      for (final adjustment in _adjustments) Dates.ymOfYmd(adjustment.date),
    }.toList();
    months.sort();
    return months;
  }

  SettlementStatus get _status => _worker.settlementStatus;

  /// 标记 / 取消标记本区间已结算。
  ///
  /// 只改状态，不动任何金额；因此即使月份已锁账也允许操作
  /// （锁账是防改账，结算是记录「钱已发」）。
  /// 取消时会追加一条变更历史，**理由选填**：留空返回空串，照常完成。
  Future<void> _toggleSettled() async {
    if (_marking) return;
    final months = _activeMonths;
    if (months.isEmpty) {
      showToast(context, '本期没有可结算的账目', isError: true);
      return;
    }
    final settle = !_status.isFullySettled;
    final prettyMonths = months
        .map((month) => '${month.substring(0, 4)}年${int.parse(month.substring(5, 7))}月')
        .join('、');
    String? reason;
    if (settle) {
      final ok = await showConfirmDialog(
        context,
        title: '标记 $prettyMonths 已结算？',
        message: '只做状态标记，不改金额、不影响计件与调整项。\n'
            '本期应付 ${Money.formatCents(_worker.netCents)} 元，'
            '其中未结 ${Money.formatCents(_worker.unsettledCents)} 元。\n'
            '标记后会归入「已结算」，方便和还没发钱的工人区分开；'
            '只想结其中几笔，请去「详细明细」逐笔标。',
        confirmText: '标记已结算',
      );
      if (!ok) return;
    } else {
      reason = await showCancelSettlementDialog(
        context,
        title: '取消已结算标记？',
        message: '取消后 $prettyMonths 会重新算作「未结算」（含已单独标记的笔数）。'
            '金额不变，随时可以再标记回来。\n'
            '可以填一句取消理由方便以后查账，也可以直接留空。',
      );
      // null = 用户放弃取消；空串 = 确认但不填理由，两者必须区分开。
      if (reason == null) return;
    }
    setState(() => _marking = true);
    try {
      await widget.services.settlementEntries.markRange(
        workerId: widget.worker.workerId,
        months: months,
        range: widget.range,
        settled: settle,
        reason: reason,
      );
      widget.services.notifyDataChanged();
      await _load();
      if (!mounted) return;
      showToast(context, settle ? '已标记为已结算' : '已取消结算标记');
    } catch (error) {
      if (!mounted) return;
      showToast(context, '操作失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  /// 打开完整变更历史（审计视图），只在详情/历史面板展示。
  Future<void> _openHistory() async {
    await showSettlementHistorySheet(
      context: context,
      services: widget.services,
      workerId: widget.worker.workerId,
      workerName: widget.worker.workerName,
      workerCode: widget.worker.workerCode,
      currentStatus: _status,
    );
    if (mounted) await _load();
  }

  /// 当前状态标识：状态 + 累计变更次数 + 最近一次（精确到秒）。
  Widget _buildStatusTrailCard(ThemeData theme) {
    final latest = _latestEvent;
    final accent = _status == SettlementStatus.settled
        ? AppTheme.success
        : (_status == SettlementStatus.partial
            ? AppTheme.warning
            : AppTheme.muted);
    return Container(
      key: const ValueKey('detail-status-trail'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '当前状态：${_status.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _historyCount == 0
                ? '共 0 次变更 · 还没标记过结算状态'
                : '共 $_historyCount 次变更 · 最近 ${latest!.signature} '
                    '${latest.action.label} 于 ${latest.timeText}',
            maxLines: 2,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppTheme.muted, height: 1.4),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('detail-open-history'),
              onPressed: _openHistory,
              icon: const Icon(Icons.history, size: 18),
              label: const Text('变更历史'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecords() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerRecordsPage(
          workerId: widget.worker.workerId,
          workerName: widget.worker.workerName,
          workerCode: widget.worker.workerCode,
          range: widget.range,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _addAdjustment() async {
    final workers = await widget.services.workers.listAll();
    if (!mounted) return;
    final Worker? target = workers
        .where((item) => item.id == widget.worker.workerId)
        .cast<Worker?>()
        .firstWhere((_) => true, orElse: () => null);
    final list = target == null ? workers : [target];
    // 默认落到当前结算区间内：在历史区间里补录，钱必须留在这一期
    final today = Dates.ymd(AppClock.now());
    final defaultDate =
        widget.range.contains(today) ? today : widget.range.end;
    final saved = await showAdjustmentSheet(
      context: context,
      services: widget.services,
      defaultDate: defaultDate,
      workers: list,
      defaultWorkerId: widget.worker.workerId,
    );
    if (saved == true) {
      widget.services.notifyDataChanged();
      await _load();
    }
  }

  Future<void> _editAdjustment(Adjustment adjustment) async {
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

  Future<void> _deleteAdjustment(Adjustment adjustment) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条${adjustment.type.label}？',
      message: '${adjustment.type.label} ${adjustment.amountLabel} 元 · ${adjustment.remark}\n'
          '删除后 30 天内可在回收站恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.services.adjustments.softDelete(adjustment.id);
      widget.services.notifyDataChanged();
      await _load();
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  /// 生成工资条长图：明细过长会自动拆成多张，避免一次渲染把内存撑爆。
  Future<void> _buildPayslip() async {
    if (_buildingPayslip) return;
    setState(() => _buildingPayslip = true);
    try {
      final images = await widget.services.payslips.buildPayslip(
        worker: widget.worker,
        range: widget.range,
        adjustments: _adjustments,
      );
      if (!mounted) return;
      await showPayslipSheet(
        context,
        images: images,
        workerName: widget.worker.workerName,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(context, '生成工资条失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _buildingPayslip = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worker = _worker;
    final net = worker.netCents;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(
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
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(worker.workerName, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${widget.range.label} · 编号 ${worker.workerCode}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.muted),
                          ),
                          SettlementBadge(_status, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
                // 金额单独限宽：金额位数多 + 超大字号时宁可整体缩小，
                // 也不能把左边的姓名/区间压成一条缝（结算状态标签就放不下了）。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('应付',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.muted)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          Money.formatCents(net),
                          maxLines: 1,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: net < 0 ? AppTheme.danger : AppTheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (_locked)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: InfoBanner(
                text: '该区间含已锁账月份，调整项不可增删改。',
                color: AppTheme.danger,
                icon: Icons.lock_outline,
              ),
            ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      _buildStatusTrailCard(theme),
                      const SizedBox(height: 12),
                      // 两个主动作：看逐条明细、标记结算状态
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _openRecords,
                            icon: const Icon(Icons.format_list_bulleted, size: 20),
                            label: const Text('详细明细'),
                          ),
                          if (_activeMonths.isNotEmpty)
                            _status.isFullySettled
                                ? TextButton.icon(
                                    onPressed: _marking ? null : _toggleSettled,
                                    icon: const Icon(Icons.undo, size: 20),
                                    label: const Text('取消已结算'),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: _marking ? null : _toggleSettled,
                                    icon: const Icon(Icons.check_circle_outline,
                                        size: 20),
                                    label: Text(
                                      _status == SettlementStatus.partial
                                          ? '标记全部已结算'
                                          : '标记本期已结算',
                                    ),
                                  ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      MutedText(
                        '「详细明细」按当前区间逐条列出每一笔：哪天、什么工序、多少件、'
                        '多少钱、是否已结算。想只结其中几笔，就在明细里逐笔点结算。',
                      ),
                      const SizedBox(height: 14),
                      Text('计件明细', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      MutedText('同一工序不同单价会分行显示，合计为逐笔取整后相加。'),
                      const SizedBox(height: 10),
                      if (worker.groups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: MutedText('本期没有计件记录'),
                        )
                      else
                        for (final group in worker.groups)
                          _buildGroupRow(theme, group),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text('调整项', style: theme.textTheme.titleMedium),
                          ),
                          if (!_locked)
                            TextButton.icon(
                              onPressed: _addAdjustment,
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('录入'),
                            ),
                        ],
                      ),
                      if (_adjustments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: MutedText(
                            '本期没有补贴 / 计时 / 扣款 / 预支。'
                            '点右上角「录入」可以补记一笔。',
                          ),
                        )
                      else
                        for (final adjustment in _adjustments)
                          _buildAdjustmentRow(theme, adjustment),
                      const SizedBox(height: 18),
                      _buildFormulaCard(theme, worker),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _buildingPayslip ? null : _buildPayslip,
                        icon: _buildingPayslip
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.receipt_long_outlined),
                        label: Text(
                          _buildingPayslip ? '正在生成…' : '生成工资条图片',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const MutedText(
                        '工资条按明细行数自动分页，可存到相册或直接发给工人。',
                        align: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupRow(ThemeData theme, PieceGroup group) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (group.overtime) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          group.overtimeSuffix,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        '${group.toyName}${group.process == Defaults.defaultProcess ? '' : ' / ${group.process}'}',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${group.quantity} 件 × '
                      '${Money.formatPrice(group.pricingPriceTenThousandth)}',
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    if (PriceRules.isTemporary(
                      recordUnitPrice: group.unitPriceTenThousandth,
                      baseUnitPrice: _basePrices[group.toyId] ?? 0,
                    ))
                      const TempPriceBadge(compact: true),
                  ],
                ),
              ],
            ),
          ),
          Text(
            Money.formatCents(group.subtotalCents),
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentRow(ThemeData theme, Adjustment adjustment) {
    final positive = adjustment.type.sign > 0;
    return InkWell(
      onTap: _locked ? null : () => _editAdjustment(adjustment),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (positive ? AppTheme.success : AppTheme.danger)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                adjustment.type.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: positive ? AppTheme.success : AppTheme.danger,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adjustment.summaryLabel,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${adjustment.date} ${adjustment.timeLabel}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.muted),
                      ),
                      if (BackfillRules.isBackfill(
                        workDate: adjustment.date,
                        createdAtMillis: adjustment.createdAt,
                        today: Dates.ymd(AppClock.now()),
                      ))
                        BackfillBadge(
                          daysEarlier: Dates.daysBetween(
                            adjustment.date,
                            Dates.ymd(AppClock.now()),
                          ),
                          compact: true,
                        ),
                      SettlementBadge(
                        adjustment.isSettled(_worker.settledMonths)
                            ? SettlementStatus.settled
                            : SettlementStatus.unsettled,
                        compact: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  Money.formatCentsSigned(adjustment.signedCents),
                  maxLines: 1,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: positive ? AppTheme.success : AppTheme.danger,
                  ),
                ),
              ),
            ),
            if (!_locked)
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, color: AppTheme.muted, size: 22),
                onPressed: () => _deleteAdjustment(adjustment),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaCard(ThemeData theme, WorkerSettlement worker) {
    final settled = worker.settledCents;
    final unsettled = worker.unsettledCents;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          KeyValueRow(
            label: '计件工资',
            value: Money.formatCents(worker.pieceCents),
          ),
          KeyValueRow(label: '补贴', value: '+${Money.formatCents(worker.bonusCents)}'),
          KeyValueRow(label: '计时', value: '+${Money.formatCents(worker.hourlyCents)}'),
          KeyValueRow(label: '扣款', value: '-${Money.formatCents(worker.deductionCents)}'),
          KeyValueRow(label: '预支', value: '-${Money.formatCents(worker.advanceCents)}'),
          const Divider(height: 16),
          KeyValueRow(
            label: '应付',
            value: '${Money.formatCents(worker.netCents)} 元',
            bold: true,
            valueColor: worker.isNegative ? AppTheme.danger : AppTheme.primary,
          ),
          KeyValueRow(
            label: '已结算',
            value: '${Money.formatCents(settled)}（${worker.settledCount} 笔）',
            valueColor: AppTheme.success,
          ),
          KeyValueRow(
            label: '未结算',
            value: '${Money.formatCents(unsettled)}（${worker.unsettledCount} 笔）',
            valueColor: unsettled == 0 ? AppTheme.muted : AppTheme.warning,
          ),
          if (worker.isNegative)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '应付为负数，请核对扣款与预支是否录错',
                style: TextStyle(fontSize: 13, color: AppTheme.danger),
              ),
            ),
        ],
      ),
    );
  }
}
