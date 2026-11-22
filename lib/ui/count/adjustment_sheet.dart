import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../core/money.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/worker.dart';
import '../../services/app_services.dart';
import '../common/date_picker_sheet.dart';
import '../common/picker.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 调整项录入（补贴 / 计时 / 扣款 / 预支）。
///
/// [initialType] 用于计数页那四个快捷入口：点「扣款」进来就默认选中扣款，
/// 少点一次。[existing] 非空时为修改模式。
Future<bool?> showAdjustmentSheet({
  required BuildContext context,
  required AppServices services,
  required String defaultDate,
  required List<Worker> workers,
  String? defaultWorkerId,
  AdjustmentType initialType = AdjustmentType.bonus,
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _AdjustmentSheet(
        services: services,
        defaultDate: defaultDate,
        workers: workers,
        defaultWorkerId: defaultWorkerId,
        initialType: initialType,
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
    this.initialType = AdjustmentType.bonus,
    this.existing,
  });

  final AppServices services;
  final String defaultDate;
  final List<Worker> workers;
  final String? defaultWorkerId;
  final AdjustmentType initialType;
  final Adjustment? existing;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _remark = TextEditingController();

  late String _date;
  late int _minuteOfDay;
  String? _workerId;
  late AdjustmentType _type;

  /// 计时是否按「工时 × 时薪」计价。false 时退回「直接填金额」。
  bool _byWorkTime = false;

  bool _saving = false;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.date ?? widget.defaultDate;
    _minuteOfDay = existing?.minuteOfDay ?? AppClock.nowMinuteOfDay();
    _workerId = existing?.workerId ??
        widget.defaultWorkerId ??
        (widget.workers.isNotEmpty ? widget.workers.first.id : null);
    _type = existing?.type ?? widget.initialType;
    if (existing != null) {
      _amount.text = Money.formatCents(existing.amountCents);
      _remark.text = existing.remark;
      _byWorkTime = existing.isByWorkTime;
      if (existing.isByWorkTime) {
        _hours.text = Money.formatHours(existing.workMinutes);
        _rate.text = Money.formatCents(existing.hourlyRateCents);
      }
    } else {
      _byWorkTime = _type == AdjustmentType.hourly;
    }
    for (final controller in [_amount, _hours, _rate]) {
      controller.addListener(_onAmountChanged);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _hours.dispose();
    _rate.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  Worker? get _worker {
    final id = _workerId;
    if (id == null) return null;
    for (final worker in widget.workers) {
      if (worker.id == id) return worker;
    }
    return null;
  }

  /// 计时模式下的工时（分钟）；输入非法返回 null。
  int? get _workMinutes => Money.tryParseHoursToMinutes(_hours.text);

  /// 计时模式下的时薪（分/小时）；输入非法返回 null。
  int? get _hourlyRate => Money.tryParseCents(_rate.text);

  bool get _hourlyByTime => _type == AdjustmentType.hourly && _byWorkTime;

  /// 真正会入账的金额（分）。
  int? get _resolvedAmount {
    if (_hourlyByTime) {
      final minutes = _workMinutes;
      final rate = _hourlyRate;
      if (minutes == null || rate == null) return null;
      if (minutes <= 0 || rate <= 0) return null;
      return Money.hourlyCents(minutes: minutes, rateCentsPerHour: rate);
    }
    return Money.tryParseCents(_amount.text);
  }

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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _minuteOfDay ~/ 60,
        minute: _minuteOfDay % 60,
      ),
      helpText: '这笔是几点登记的？',
    );
    if (picked == null || !mounted) return;
    setState(() => _minuteOfDay = picked.hour * 60 + picked.minute);
  }

  Future<void> _save() async {
    if (_saving) return;
    final worker = _worker;
    if (worker == null) {
      showToast(context, '请选择工人', isError: true);
      return;
    }
    final amount = _resolvedAmount;
    if (amount == null) {
      showToast(
        context,
        _hourlyByTime ? '工时或时薪填得不对，请检查' : '金额要填大于 0 的数字',
        isError: true,
      );
      return;
    }
    if (amount <= 0) {
      showToast(context, '金额算出来是 0，请检查工时与时薪', isError: true);
      return;
    }
    if (amount > Limits.maxAdjustmentCents) {
      showToast(context, '金额过大，请检查是不是多打了一个 0', isError: true);
      return;
    }
    if (_remark.text.trim().isEmpty) {
      showToast(context, '${_type.remarkLabel}必填，方便月底核对', isError: true);
      return;
    }

    final minutes = _hourlyByTime ? (_workMinutes ?? 0) : 0;
    final rate = _hourlyByTime ? (_hourlyRate ?? 0) : 0;

    setState(() => _saving = true);
    final existing = widget.existing;
    try {
      if (existing != null) {
        await widget.services.adjustments.update(
          existing: existing,
          date: _date,
          minuteOfDay: _minuteOfDay,
          type: _type,
          amountCents: amount,
          workMinutes: minutes,
          hourlyRateCents: rate,
          remark: _remark.text,
        );
      } else {
        await widget.services.adjustments.create(
          date: _date,
          minuteOfDay: _minuteOfDay,
          worker: worker,
          type: _type,
          amountCents: amount,
          workMinutes: minutes,
          hourlyRateCents: rate,
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
    final amount = _resolvedAmount;
    final positive = _type.isPositive;

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
            MutedText('补贴、计时工资计入应付；扣款、预支从应付里扣除。'),
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
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_date, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(Dates.hhmm(_minuteOfDay)),
                  ),
                ),
              ],
            ),
            if (CnHolidays.of(_date) != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HolidayBadge(CnHolidays.of(_date)!, compact: true),
                  MutedText('这笔调整项的日期'),
                ],
              ),
            ],
            if (_date.compareTo(Dates.ymd(AppClock.now())) < 0) ...[
              const SizedBox(height: 6),
              MutedText('今天录入，账算在 $_date（明细里会标「补录」）'),
            ],
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
                    selectedColor:
                        type.sign > 0 ? AppTheme.success : AppTheme.danger,
                    onSelected: (_) => setState(() {
                      _type = type;
                      // 切到计时默认按工时算；切走则回到「直接填金额」
                      _byWorkTime = type == AdjustmentType.hourly;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_type == AdjustmentType.hourly) ...[
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('按工时 × 时薪'),
                    selected: _byWorkTime,
                    onSelected: (_) => setState(() => _byWorkTime = true),
                  ),
                  ChoiceChip(
                    label: const Text('直接填金额'),
                    selected: !_byWorkTime,
                    onSelected: (_) => setState(() => _byWorkTime = false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_byWorkTime)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hours,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          labelText: '工时',
                          hintText: '3.5',
                          suffixText: '小时',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _rate,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          labelText: '时薪',
                          hintText: '25',
                          suffixText: '元/时',
                        ),
                      ),
                    ),
                  ],
                )
              else
                TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style:
                      const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: '计时金额（元）',
                    helperText: positive ? '这一项会加到应付里' : '这一项会从应付里扣',
                    suffixText: '元',
                  ),
                ),
            ] else
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: '金额（元）',
                  helperText: positive ? '这一项会加到应付里' : '这一项会从应付里扣',
                  suffixText: '元',
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (positive ? AppTheme.success : AppTheme.danger)
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    color: positive ? AppTheme.success : AppTheme.danger,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _type.label,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        amount == null
                            ? '—'
                            : Money.formatCentsSigned(positive ? amount : -amount),
                        maxLines: 1,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: positive ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '元',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remark,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                labelText: '${_type.remarkLabel}（必填）',
                hintText: _type.remarkHint,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _saving
                    ? '正在保存…'
                    : (widget.existing == null ? '保存调整项' : '保存修改'),
              ),
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
