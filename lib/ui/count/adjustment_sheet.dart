import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/worker.dart';
import '../../services/app_services.dart';
import '../common/picker.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 调整项录入（补贴 / 计时 / 扣款 / 预支）。
Future<bool?> showAdjustmentSheet({
  required BuildContext context,
  required AppServices services,
  required String defaultDate,
  required List<Worker> workers,
  String? defaultWorkerId,
  Adjustment? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _AdjustmentSheet(
        services: services,
        defaultDate: defaultDate,
        workers: workers,
        defaultWorkerId: defaultWorkerId,
        existing: existing,
      ),
    ),
  );
}

class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet({
    required this.services,
    required this.defaultDate,
    required this.workers,
    this.defaultWorkerId,
    this.existing,
  });

  final AppServices services;
  final String defaultDate;
  final List<Worker> workers;
  final String? defaultWorkerId;
  final Adjustment? existing;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _remark = TextEditingController();

  late String _date;
  String? _workerId;
  AdjustmentType _type = AdjustmentType.bonus;
  bool _saving = false;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.date ?? widget.defaultDate;
    _workerId = existing?.workerId ??
        widget.defaultWorkerId ??
        (widget.workers.isNotEmpty ? widget.workers.first.id : null);
    if (existing != null) {
      _type = existing.type;
      _amount.text = Money.formatCents(existing.amountCents);
      _remark.text = existing.remark;
    }
    _amount.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _remark.dispose();
    super.dispose();
  }

  Worker? get _worker {
    final id = _workerId;
    if (id == null) return null;
    for (final worker in widget.workers) {
      if (worker.id == id) return worker;
    }
    return null;
  }

  int? get _amountCents => Money.tryParseCents(_amount.text);

  Future<void> _pickWorker() async {
    final picked = await showSearchPicker<Worker>(
      context: context,
      title: '选择工人',
      items: widget.workers,
      nameOf: (item) => item.name,
      subtitleOf: (item) => '编号 ${item.code}',
      initialsOf: (item) => item.pinyinInitials,
      codeOf: (item) => item.code,
      badgeOf: (item) => item.pinyinInitials,
    );
    if (picked != null) setState(() => _workerId = picked.id);
  }

  Future<void> _pickDate() async {
    final picked = await pickRecordDate(context, initial: _date);
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final worker = _worker;
    if (worker == null) {
      showToast(context, '请选择工人', isError: true);
      return;
    }
    final amount = _amountCents;
    if (amount == null || amount <= 0) {
      showToast(context, '金额要填大于 0 的数字', isError: true);
      return;
    }
    if (_remark.text.trim().isEmpty) {
      showToast(context, '备注必填，方便月底核对', isError: true);
      return;
    }

    setState(() => _saving = true);
    final existing = widget.existing;
    try {
      if (existing != null) {
        await widget.services.adjustments.update(
          existing: existing,
          date: _date,
          type: _type,
          amountCents: amount,
          remark: _remark.text,
        );
      } else {
        await widget.services.adjustments.create(
          date: _date,
          worker: worker,
          type: _type,
          amountCents: amount,
          remark: _remark.text,
          adjustmentId: _pendingId ??= IdGen.next(),
        );
      }
      _pendingId = null;
      widget.services.notifyDataChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败：$error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worker = _worker;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5D9E0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.existing == null ? '录入调整项' : '修改调整项',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            MutedText('补贴、计时工资计入应付；扣款、预支从应付中扣除。'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickWorker,
                    icon: const Icon(Icons.person_outline),
                    label: Text(
                      worker?.name ?? '选择工人',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_date),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final type in AdjustmentType.values)
                  ChoiceChip(
                    label: Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _type == type ? Colors.white : null,
                      ),
                    ),
                    selected: _type == type,
                    selectedColor: type.sign > 0 ? AppTheme.success : AppTheme.danger,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: '金额（元）',
                helperText: _type.sign > 0 ? '这一项会加到应付里' : '这一项会从应付里扣',
                suffixText: '元',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remark,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                labelText: '备注（必填）',
                hintText: '如：全勤奖 / 打包 3 小时 / 预支生活费',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? '正在保存…' : (widget.existing == null ? '保存调整项' : '保存修改')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
