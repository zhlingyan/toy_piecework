import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/piece_record.dart';
import '../../data/models/toy.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../../domain/rules/overtime_rules.dart';
import '../../services/app_services.dart';
import '../common/date_picker_sheet.dart';
import '../common/picker.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 修改一笔已录入的计件。
///
/// 规则：
/// * 改数量沿用原单价快照重算；
/// * 只改备注时小计保持不变（不重新取整）；
/// * 更换工序若单价不同，必须二次确认新单价。
Future<bool?> showRecordEditSheet({
  required BuildContext context,
  required AppServices services,
  required PieceRecord record,
  required List<Toy> toys,
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
      child: _RecordEditSheet(services: services, record: record, toys: toys),
    ),
  );
}

class _RecordEditSheet extends StatefulWidget {
  const _RecordEditSheet({
    required this.services,
    required this.record,
    required this.toys,
  });

  final AppServices services;
  final PieceRecord record;
  final List<Toy> toys;

  @override
  State<_RecordEditSheet> createState() => _RecordEditSheetState();
}

class _RecordEditSheetState extends State<_RecordEditSheet> {
  late final TextEditingController _quantity;
  late final TextEditingController _remark;
  late final TextEditingController _price;

  late String _date;
  late String _toyId;
  late String _toyName;
  late String _process;
  late int _unitPrice;
  late int _minuteOfDay;
  late bool _overtime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _date = record.date;
    _toyId = record.toyId;
    _toyName = record.toyNameSnapshot;
    _process = record.processSnapshot;
    _unitPrice = record.unitPriceSnapshot;
    _minuteOfDay = record.minuteOfDay;
    _overtime = record.overtime;
    _quantity = TextEditingController(text: '${record.quantity}')
      ..addListener(() => setState(() {}));
    _remark = TextEditingController(text: record.remark);
    _price = TextEditingController(text: Money.formatPrice(record.unitPriceSnapshot))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _remark.dispose();
    _price.dispose();
    super.dispose();
  }

  int? get _quantityValue {
    final text = Money.normalizeDigits(_quantity.text).trim();
    final value = int.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  int? get _priceValue {
    final value = Money.tryParsePrice(_price.text);
    if (value == null || value < 0) return null;
    return value;
  }

  /// 加班时按设置口径换算后的价格；不加班返回 null。
  OvertimePricing? get _overtimePricing {
    final base = _priceValue;
    if (!_overtime || base == null) return null;
    final toy = _resolvedToy;
    final settings = widget.services.settings;
    if (toy != null) {
      return OvertimeRules.resolve(
        toy: toy,
        basePriceTenThousandth: base,
        mode: settings.overtimeMode,
        multiplierPerMille: settings.overtimeMultiplierPerMille,
      );
    }
    // 档案已被删/归档时没有 Toy 对象，退化为纯倍率计算
    final multiplier = settings.overtimeMultiplierPerMille;
    return OvertimePricing(
      priceTenThousandth: Money.applyMultiplier(base, multiplier),
      multiplierPerMille: multiplier,
    );
  }

  Toy? get _resolvedToy {
    for (final toy in widget.toys) {
      if (toy.id == _toyId) return toy;
    }
    return null;
  }

  int? get _pricingPrice =>
      _overtime ? _overtimePricing?.priceTenThousandth : _priceValue;

  int? get _subtotal {
    final quantity = _quantityValue;
    final price = _pricingPrice;
    if (quantity == null || price == null) return null;
    return Money.subtotalCents(quantity: quantity, priceTenThousandth: price);
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
      helpText: '这笔活是几点做完的？',
    );
    if (picked == null || !mounted) return;
    setState(() => _minuteOfDay = picked.hour * 60 + picked.minute);
  }

  Future<void> _changeToy() async {
    if (widget.toys.isEmpty) {
      showToast(context, '没有可用的玩具档案', isError: true);
      return;
    }
    final picked = await showSearchPicker<Toy>(
      context: context,
      title: '更换玩具 / 工序',
      items: widget.toys,
      nameOf: (item) => item.displayName,
      subtitleOf: (item) => '单价 ${item.priceLabel} 元',
      initialsOf: (item) => item.pinyinInitials,
      badgeOf: (item) => item.priceLabel,
    );
    if (picked == null) return;
    if (!mounted) return;

    var newPrice = picked.unitPriceTenThousandth;
    if (newPrice != _unitPrice) {
      final ok = await showConfirmDialog(
        context,
        title: '新工序的单价不一样',
        message: '「${picked.displayName}」的单价是 ${picked.priceLabel} 元，'
            '原来是 ${Money.formatPrice(_unitPrice)} 元。\n\n'
            '改用新单价后，这一笔的小计会重新计算。',
        confirmText: '用新单价',
      );
      if (!ok) return;
    } else {
      newPrice = _unitPrice;
    }

    setState(() {
      _toyId = picked.id;
      _toyName = picked.name;
      _process = picked.process;
      _unitPrice = newPrice;
      _price.text = Money.formatPrice(newPrice);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final quantity = _quantityValue;
    final price = _priceValue;
    if (quantity == null) {
      showToast(context, '数量要填大于 0 的整数', isError: true);
      return;
    }
    if (price == null) {
      showToast(context, '单价格式不对，最多 4 位小数', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.services.records.update(
        existing: widget.record,
        date: _date,
        quantity: quantity,
        remark: _remark.text,
        unitPriceTenThousandth: price,
        minuteOfDay: _minuteOfDay,
        overtime: _overtime,
        overtimePriceTenThousandth: _overtimePricing?.priceTenThousandth,
        overtimeMultiplier: _overtimePricing?.multiplierPerMille,
        toyId: _toyId,
        toyNameSnapshot: _toyName,
        processSnapshot: _process,
      );
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

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这笔记录？',
      message: '删除后 30 天内可在回收站恢复，超过 30 天将不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.services.records.softDelete(widget.record.id);
      widget.services.notifyDataChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;
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
            Text('修改这一笔', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            MutedText('工人：${record.workerNameSnapshot}（工人不可改，记错了请删掉重记）'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _changeToy,
                    icon: const Icon(Icons.toys_outlined),
                    label: Text(
                      '$_toyName${_process == '整件' ? '' : ' / $_process'}',
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
            const SizedBox(height: 6),
            // 两个时间分开写清楚：改上面那排不会改「录入时间」
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MutedText('录入于 ${record.createdAtLabel}'),
                if (CnHolidays.of(_date) != null)
                  HolidayBadge(CnHolidays.of(_date)!, compact: true),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: _overtime
                    ? AppTheme.warning.withValues(alpha: 0.08)
                    : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _overtime
                      ? AppTheme.warning.withValues(alpha: 0.4)
                      : const Color(0xFFE6E9EF),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _overtime ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                    color: _overtime ? AppTheme.warning : AppTheme.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _overtime ? '加班' : '正常班',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_overtime && _overtimePricing != null)
                          Text(
                            '${_overtimePricing!.priceLabel} 元/件'
                            '（×${_overtimePricing!.multiplierLabel}）',
                            style: const TextStyle(fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _overtime,
                    onChanged: (value) => setState(() => _overtime = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(labelText: '数量（件）'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(labelText: '单价（元）'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remark,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text('小计',
                      style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.muted)),
                  const Spacer(),
                  Text(
                    _subtotal == null ? '—' : Money.formatCents(_subtotal!),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.primary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('元',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted)),
                ],
              ),
            ),
            if (_date != record.date)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InfoBanner(
                  text: '日期改动后，原月份与目标月份都会做锁账检查。',
                  color: AppTheme.primary,
                  icon: Icons.swap_horiz,
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
              label: Text(_saving ? '正在保存…' : '保存修改'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              label: const Text('删除这笔', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
