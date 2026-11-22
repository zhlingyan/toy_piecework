import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/settlement.dart';
import '../../data/models/worker.dart';
import '../../services/app_services.dart';
import '../common/export_sheet.dart';
import '../common/ui_kit.dart';
import '../count/adjustment_sheet.dart';
import '../theme.dart';

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
  bool _loading = true;
  bool _locked = false;
  bool _buildingPayslip = false;

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
    if (!mounted) return;
    setState(() {
      _adjustments = adjustments;
      _locked = widget.range.months.any(lockedMonths.contains);
      _loading = false;
    });
  }

  Future<void> _addAdjustment() async {
    final workers = await widget.services.workers.listAll();
    if (!mounted) return;
    final Worker? target = workers
        .where((item) => item.id == widget.worker.workerId)
        .cast<Worker?>()
        .firstWhere((_) => true, orElse: () => null);
    final list = target == null ? workers : [target];
    final saved = await showAdjustmentSheet(
      context: context,
      services: widget.services,
      defaultDate: Dates.ymd(DateTime.now()),
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
    final worker = widget.worker;
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
                      Text(
                        '${widget.range.label} · 编号 ${worker.workerCode}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('应付',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
                    Text(
                      Money.formatCents(net),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: net < 0 ? AppTheme.danger : AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
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
                          child: MutedText('本期没有补贴 / 计时 / 扣款 / 预支'),
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
                Text(
                  '${group.quantity} 件 × ${Money.formatPrice(group.pricingPriceTenThousandth)} 元',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
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
                    adjustment.remark,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    adjustment.date,
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Text(
              Money.formatCentsSigned(adjustment.signedCents),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: positive ? AppTheme.success : AppTheme.danger,
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
