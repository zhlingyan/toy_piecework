import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../core/money.dart';
import '../../data/models/piece_record.dart';
import '../../data/models/toy.dart';
import '../../data/models/worker.dart';
import '../../domain/rules/overtime_rules.dart';
import '../../services/app_services.dart';
import '../../state/selection_state.dart';
import '../common/picker.dart';
import '../common/ui_kit.dart';
import '../theme.dart';
import 'adjustment_sheet.dart';
import 'record_edit_sheet.dart';

/// 计数页：极速连录 + 防呆。
class CountPage extends StatefulWidget {
  const CountPage({super.key, required this.selection});

  final SelectionState selection;

  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _remark = TextEditingController();
  final TextEditingController _manualPrice = TextEditingController();

  AppServices? _services;
  List<Worker> _workers = const [];
  List<Toy> _toys = const [];
  List<PieceRecord> _records = const [];
  bool _locked = false;
  bool _loading = true;
  bool _saving = false;
  bool _manualPriceEnabled = false;

  /// 业务发生时刻（当天第几分钟）。默认取当前时间，补录可改。
  int _minuteOfDay = AppClock.nowMinuteOfDay();

  /// 是否加班。
  bool _overtime = false;

  /// 用户手动动过加班开关后，就不再让「超时自动预勾」覆盖他的选择。
  bool _overtimeManual = false;

  int _loadedVersion = -1;
  String _loadedDate = '';

  /// 点击保存时生成的固定主键：双击重复提交会被数据库主键冲突挡掉。
  String? _pendingRecordId;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
    _quantity.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _quantity.dispose();
    _remark.dispose();
    _manualPrice.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    if (_loadedDate != widget.selection.date) {
      _reload();
    } else {
      setState(() {});
    }
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _services = services;
    if (_loadedVersion != services.refresh.version) {
      _loadedVersion = services.refresh.version;
      _reload();
    }
  }

  Future<void> _reload() async {
    final services = _services;
    if (services == null) return;
    final date = widget.selection.date;
    _loadedDate = date;
    if (mounted) setState(() => _loading = true);

    final workers = await services.workers.listActive();
    final toys = await services.toys.listActive();
    final records = await services.records.listByDate(date);
    final locked = Dates.isValidYmd(date)
        ? await services.months.isLocked(Dates.ymOfYmd(date))
        : false;
    if (!mounted) return;
    setState(() {
      _workers = workers;
      _toys = toys;
      _records = records;
      _locked = locked;
      _loading = false;
      _syncOvertimeAuto(notify: false);
    });
  }

  /// 按「是否晚于下班时间」自动预勾加班。
  ///
  /// 只是初始值：用户一旦手动动过开关（[_overtimeManual]），
  /// 就再也不覆盖他的选择——晚上补录白天干的活不该被硬判成加班。
  void _syncOvertimeAuto({bool notify = true}) {
    final settings = _services?.settings;
    if (settings == null || _overtimeManual) return;
    final auto = OvertimeRules.shouldPrecheckOvertime(
      minuteOfDay: _minuteOfDay,
      workEndMinute: settings.workEndMinute,
      autoDetect: settings.overtimeAutoDetect,
    );
    if (auto == _overtime) return;
    if (notify) {
      setState(() => _overtime = auto);
    } else {
      _overtime = auto;
    }
  }

  /// 改「具体时间」（精确到分钟）。
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minuteOfDay ~/ 60, minute: _minuteOfDay % 60),
      helpText: '这笔活是几点做完的？',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => MediaQuery(
        // 时间选择器在超大字号下会被挤压，这里单独限一下缩放
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context).clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.3,
              ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _minuteOfDay = picked.hour * 60 + picked.minute;
      _syncOvertimeAuto(notify: false);
    });
  }

  Worker? get _worker {
    final id = widget.selection.workerId;
    if (id == null) return null;
    for (final worker in _workers) {
      if (worker.id == id) return worker;
    }
    return null;
  }

  Toy? get _toy {
    final id = widget.selection.toyId;
    if (id == null) return null;
    for (final toy in _toys) {
      if (toy.id == id) return toy;
    }
    return null;
  }

  int? get _quantityValue {
    final text = Money.normalizeDigits(_quantity.text).trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// 正常班单价（可能来自手填）。
  int? get _effectivePrice {
    if (_manualPriceEnabled) {
      final parsed = Money.tryParsePrice(_manualPrice.text);
      if (parsed != null && parsed >= 0) return parsed;
      return null;
    }
    return _toy?.unitPriceTenThousandth;
  }

  /// 加班时的实际单价与倍率；不加班返回 null。
  ///
  /// 口径由设置决定（倍数 / 玩具加班单价），算法只有
  /// [OvertimeRules.resolve] 一处，界面上看到的就是最终入账的。
  OvertimePricing? get _overtimePricing {
    final toy = _toy;
    final base = _effectivePrice;
    final settings = _services?.settings;
    if (!_overtime || toy == null || base == null || settings == null) {
      return null;
    }
    return OvertimeRules.resolve(
      toy: toy,
      basePriceTenThousandth: base,
      mode: settings.overtimeMode,
      multiplierPerMille: settings.overtimeMultiplierPerMille,
    );
  }

  /// 真正参与计算的单价。
  int? get _pricingPrice => _overtime ? _overtimePricing?.priceTenThousandth : _effectivePrice;

  int? get _subtotal {
    final quantity = _quantityValue;
    final price = _pricingPrice;
    if (quantity == null || price == null) return null;
    return Money.subtotalCents(quantity: quantity, priceTenThousandth: price);
  }

  Future<void> _pickWorker() async {
    if (_workers.isEmpty) {
      showToast(context, '还没有工人档案，请先到「设置 → 工人档案」建档', isError: true);
      return;
    }
    final picked = await showSearchPicker<Worker>(
      context: context,
      title: '选择工人',
      items: _workers,
      nameOf: (item) => item.name,
      subtitleOf: (item) => '编号 ${item.code}',
      initialsOf: (item) => item.pinyinInitials,
      codeOf: (item) => item.code,
      badgeOf: (item) => item.pinyinInitials,
      emptyHint: '没有匹配的工人',
      emptyActionHint: '到「设置 → 工人档案」新增',
    );
    if (picked != null) widget.selection.workerId = picked.id;
  }

  Future<void> _pickToy() async {
    if (_toys.isEmpty) {
      showToast(context, '还没有玩具工序档案，请先到「设置 → 玩具工序」建档', isError: true);
      return;
    }
    final picked = await showSearchPicker<Toy>(
      context: context,
      title: '选择玩具与工序',
      items: _toys,
      nameOf: (item) => item.displayName,
      subtitleOf: (item) => '单价 ${item.priceLabel} 元',
      initialsOf: (item) => item.pinyinInitials,
      badgeOf: (item) => item.priceLabel,
      emptyHint: '没有匹配的玩具',
      emptyActionHint: '到「设置 → 玩具工序」新增',
    );
    if (picked != null) {
      widget.selection.toyId = picked.id;
      setState(() {});
    }
  }

  Future<void> _changeDate() async {
    final picked = await pickRecordDate(context, initial: widget.selection.date);
    if (picked == null) return;
    widget.selection.date = picked;
  }

  Future<void> _save() async {
    if (_saving) return;
    final services = _services;
    final worker = _worker;
    final toy = _toy;
    if (services == null) return;
    if (worker == null) {
      showToast(context, '请先选择工人', isError: true);
      return;
    }
    if (toy == null) {
      showToast(context, '请先选择玩具与工序', isError: true);
      return;
    }
    final quantity = _quantityValue;
    if (quantity == null) {
      showToast(context, '数量要填大于 0 的整数', isError: true);
      return;
    }
    final price = _effectivePrice;
    if (price == null) {
      showToast(context, '单价格式不对，最多 4 位小数', isError: true);
      return;
    }
    final pricing = _overtimePricing;
    final pricingPrice = _overtime ? pricing?.priceTenThousandth : price;
    if (pricingPrice == null) {
      showToast(context, '加班单价算不出来，请检查玩具档案或加班设置', isError: true);
      return;
    }
    if (_locked) {
      showToast(context, '该月份已锁账，需先到结算页解锁', isError: true);
      return;
    }

    final subtotal =
        Money.subtotalCents(quantity: quantity, priceTenThousandth: pricingPrice);

    // 防呆：超大件数或金额二次确认
    final needConfirm = quantity > Limits.confirmQuantityAbove ||
        subtotal > Limits.confirmSubtotalCentsAbove;
    if (needConfirm) {
      final ok = await showConfirmDialog(
        context,
        title: '请再确认一次',
        message: '本次录入 ${worker.name} × ${toy.displayName}\n'
            '时间 ${widget.selection.date} ${Dates.hhmm(_minuteOfDay)}'
            '${_overtime ? '（加班 ×${pricing?.multiplierLabel}）' : ''}\n'
            '数量 $quantity 件，小计 ${Money.formatCents(subtotal)} 元\n'
            '数字是不是填多了？',
        confirmText: '确认无误',
      );
      if (!ok) return;
    }

    setState(() => _saving = true);
    final recordId = _pendingRecordId ??= IdGen.nextRecordId();
    try {
      final record = await services.records.create(
        date: widget.selection.date,
        worker: worker,
        toy: toy,
        quantity: quantity,
        remark: _remark.text,
        recordId: recordId,
        unitPriceTenThousandth: _manualPriceEnabled ? price : null,
        minuteOfDay: _minuteOfDay,
        overtime: _overtime,
        overtimePriceTenThousandth: pricing?.priceTenThousandth,
        overtimeMultiplier: pricing?.multiplierPerMille ?? 1000,
      );
      _pendingRecordId = null;
      if (!mounted) return;
      _quantity.clear();
      _remark.clear();
      if (!_manualPriceEnabled) _manualPrice.clear();
      if (!services.settings.keepWorker) widget.selection.workerId = null;
      if (!services.settings.keepToy) widget.selection.toyId = null;
      services.notifyDataChanged();
      await _reload();
      if (!mounted) return;
      showToast(
        context,
        '已记账：${record.workerNameSnapshot} ${record.quantity} 件 '
        '${Money.formatCents(record.subtotalCents)} 元',
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '保存失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAdjustment() async {
    final services = _services;
    if (services == null) return;
    if (_workers.isEmpty) {
      showToast(context, '还没有工人档案，请先建档', isError: true);
      return;
    }
    final saved = await showAdjustmentSheet(
      context: context,
      services: services,
      defaultDate: widget.selection.date,
      defaultWorkerId: widget.selection.workerId,
      workers: _workers,
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _editRecord(PieceRecord record) async {
    final services = _services;
    if (services == null) return;
    final changed = await showRecordEditSheet(
      context: context,
      services: services,
      record: record,
      toys: _toys,
    );
    if (changed == true) await _reload();
  }

  Future<void> _deleteRecord(PieceRecord record) async {
    final services = _services;
    if (services == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除这笔记录？',
      message: '${record.workerNameSnapshot} ${record.toyNameSnapshot} '
          '× ${record.quantity}\n删除后 30 天内可在回收站恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await services.records.softDelete(record.id);
      services.notifyDataChanged();
      await _reload();
      if (!mounted) return;
      showToast(context, '已移到回收站，30 天内可恢复');
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worker = _worker;
    final toy = _toy;
    final subtotal = _subtotal;
    final date = widget.selection.date;
    final isToday = date == Dates.ymd(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('计数'),
        centerTitle: false,
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _buildDateBar(theme, date, isToday),
                if (_locked) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    text: '${Dates.ymOfYmd(date)} 已锁账，本页只能查看，不能新增或修改。',
                    color: AppTheme.danger,
                    icon: Icons.lock_outline,
                  ),
                ],
                const SizedBox(height: 14),
                _buildSelectorCard(
                  theme: theme,
                  label: '工人',
                  value: worker?.name,
                  hint: '点这里选工人',
                  subtitle: worker == null ? '支持拼音首字母搜索' : '编号 ${worker.code}',
                  icon: Icons.person_outline,
                  onTap: _pickWorker,
                  accent: AppTheme.primary,
                ),
                const SizedBox(height: 10),
                _buildSelectorCard(
                  theme: theme,
                  label: '玩具 / 工序',
                  value: toy?.displayName,
                  hint: '点这里选玩具与工序',
                  subtitle: toy == null ? '单价会自动带出' : '单价 ${toy.priceLabel} 元',
                  icon: Icons.toys_outlined,
                  onTap: _pickToy,
                  accent: const Color(0xFF7A3E00),
                ),
                const SizedBox(height: 14),
                _buildQuantityCard(theme, subtotal),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: (_saving || _locked) ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 26),
                        label: Text(_saving ? '正在保存…' : '保存这一笔'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openAdjustment,
                        icon: const Icon(Icons.add_card_outlined),
                        label: const Text('调整项'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildKeepSwitches(theme),
                const SizedBox(height: 8),
                SectionCard(
                  title: '$date 的流水',
                  trailing: Text(
                    '${_records.length} 笔',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                  ),
                  child: _records.isEmpty
                      ? const EmptyState(
                          title: '这天还没有流水',
                          hint: '上面选好工人和工序，填数量就能记一笔',
                          icon: Icons.playlist_add,
                        )
                      : Column(
                          children: [
                            for (var index = 0; index < _records.length; index++) ...[
                              if (index > 0) const Divider(height: 20),
                              _buildRecordRow(theme, _records[index]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildDateBar(ThemeData theme, String date, bool isToday) {
    final mutedStyle =
        theme.textTheme.bodyLarge?.copyWith(color: AppTheme.muted);
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.event_outlined, size: 22, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isToday ? '$date（今天）' : date,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isToday ? AppTheme.primary : AppTheme.danger,
                ),
              ),
            ),
            TextButton(onPressed: _changeDate, child: const Text('改日期')),
          ],
        ),
        Row(
          children: [
            Icon(Icons.schedule_outlined, size: 22, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '记账时间 ${Dates.hhmm(_minuteOfDay)}',
                style: mutedStyle,
              ),
            ),
            TextButton(onPressed: _pickTime, child: const Text('改时间')),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectorCard({
    required ThemeData theme,
    required String label,
    required String? value,
    required String hint,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required Color accent,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasValue ? accent.withValues(alpha: 0.35) : const Color(0xFFE0E4EB),
              width: hasValue ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasValue ? value : hint,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: hasValue ? const Color(0xFF1B2430) : AppTheme.primary,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityCard(ThemeData theme, int? subtotal) {
    final price = _effectivePrice;
    return SectionCard(
      title: '数量',
      trailing: TextButton(
        onPressed: () {
          setState(() {
            _manualPriceEnabled = !_manualPriceEnabled;
            if (_manualPriceEnabled && _manualPrice.text.isEmpty && _toy != null) {
              _manualPrice.text = _toy!.priceLabel;
            }
          });
        },
        child: Text(_manualPriceEnabled ? '用档案单价' : '改单价'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(fontSize: 36, color: Color(0xFFB6BDC9)),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (_manualPriceEnabled) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _manualPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: '本次单价（元，最多 4 位小数）',
                helperText: '补录过去日期时，可填当时的单价',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          _buildOvertimeRow(theme),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: (_overtime ? AppTheme.warning : AppTheme.primary)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 单价说明单独一行，超大字号下自动换行，不会把金额挤出去
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '小计',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppTheme.muted),
                    ),
                    if (price != null)
                      Text(
                        _overtime && _overtimePricing != null
                            ? '${_quantityValue ?? 0} 件 × ${_overtimePricing!.priceLabel}'
                                '（加班 ×${_overtimePricing!.multiplierLabel}）'
                            : '${_quantityValue ?? 0} × ${Money.formatPrice(price)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.muted),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        subtotal == null ? '—' : Money.formatCents(subtotal),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: _overtime ? AppTheme.warning : AppTheme.primary,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '元',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remark,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              labelText: '备注（可不填）',
              hintText: '如：蓝色款 / 返工',
            ),
          ),
        ],
      ),
    );
  }

  /// 加班开关：打开后单价按设置的口径换算，小计实时跟着变。
  Widget _buildOvertimeRow(ThemeData theme) {
    final settings = _services?.settings;
    final toy = _toy;
    final pricing = _overtimePricing;

    String hint;
    if (!_overtime) {
      hint = '点右侧开关，标记这一笔是加班干的';
    } else if (pricing == null) {
      hint = '选好玩具与工序后，才能算出加班单价';
    } else if (settings?.overtimeMode == OvertimeMode.unitPrice &&
        toy != null &&
        !toy.hasOvertimePrice) {
      hint = '「${toy.name}」没填加班单价，已按 ×${pricing.multiplierLabel} 兜底';
    } else {
      final base = _effectivePrice;
      hint = base == null
          ? '加班单价 ${pricing.priceLabel} 元'
          : '单价 ${Money.formatPrice(base)} → ${pricing.priceLabel} 元'
              '（×${pricing.multiplierLabel}）';
    }

    return Container(
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _overtime ? AppTheme.warning : null,
                  ),
                ),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _overtime,
            onChanged: (value) => setState(() {
              _overtime = value;
              // 手动选择优先级最高，之后的自动预勾不再覆盖
              _overtimeManual = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildKeepSwitches(ThemeData theme) {
    final settings = _services?.settings;
    if (settings == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => SectionCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              value: settings.keepWorker,
              onChanged: (value) => settings.setKeepWorker(value),
              title: const Text('保存后保留工人'),
              subtitle: const Text('关掉后每记一笔都要重新选人', style: TextStyle(fontSize: 14)),
              dense: true,
            ),
            SwitchListTile(
              value: settings.keepToy,
              onChanged: (value) => settings.setKeepToy(value),
              title: const Text('保存后保留工序'),
              subtitle: const Text('关掉后每记一笔都要重新选货', style: TextStyle(fontSize: 14)),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordRow(ThemeData theme, PieceRecord record) {
    return InkWell(
      onTap: _locked ? null : () => _editRecord(record),
      onLongPress: _locked ? null : () => _deleteRecord(record),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间放最前面：车间里最常问的就是「几点记的这笔」
                  Row(
                    children: [
                      Text(
                        record.timeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (record.overtime) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '加班 ×${record.overtimeMultiplierLabel}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          '${record.workerNameSnapshot} · ${record.toyNameSnapshot}'
                          '${record.processSnapshot == Defaults.defaultProcess ? '' : ' / ${record.processSnapshot}'}',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${record.quantity} 件 × ${record.pricingPriceLabel}'
                    '${record.remark.isEmpty ? '' : ' · ${record.remark}'}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Text(
              Money.formatCents(record.subtotalCents),
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            if (!_locked)
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, color: AppTheme.muted),
                onPressed: () => _deleteRecord(record),
              ),
          ],
        ),
      ),
    );
  }
}
