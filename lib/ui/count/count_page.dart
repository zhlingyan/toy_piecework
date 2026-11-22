import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/id_gen.dart';
import '../../core/money.dart';
import '../../data/models/adjustment.dart';
import '../../data/models/piece_record.dart';
import '../../data/models/settlement_state.dart';
import '../../data/models/toy.dart';
import '../../data/models/worker.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import '../../domain/rules/backfill_rules.dart';
import '../../domain/rules/overtime_rules.dart';
import '../../domain/rules/pager.dart';
import '../../domain/rules/price_rules.dart';
import '../../domain/rules/settlement_rules.dart';
import '../../services/app_services.dart';
import '../../state/selection_state.dart';
import '../common/date_picker_sheet.dart';
import '../common/picker.dart';
import '../common/search_field.dart';
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

  /// 流水查找框：按工人姓名 / 工号筛当天的流水。
  final TextEditingController _flowSearch = TextEditingController();
  final FocusNode _quantityFocus = FocusNode();

  AppServices? _services;
  List<Worker> _workers = const [];
  List<Toy> _toys = const [];
  List<PieceRecord> _records = const [];

  /// 当天的调整项（补贴 / 计时 / 扣款 / 预支）。
  List<Adjustment> _adjustments = const [];
  bool _locked = false;
  bool _loading = true;
  bool _saving = false;
  bool _manualPriceEnabled = false;

  /// 玩具档案的当前单价：`toyId -> 单价`。
  ///
  /// 只用来判断「这一笔是不是临时调价」，**不参与计算**——
  /// 真正入账的是流水自己的单价快照，档案怎么变都不会改历史。
  Map<String, int> _basePrices = const {};

  /// 全库结算状态快照（逐笔 `settled_at` + 整月 `workerId|month` 标记）。
  ///
  /// 与结算页聚合 SQL 同源，由 `SettlementMarkRepository.loadState()` 一次读出。
  /// 之前这里存的是「该月已结算的工人 id 集合」，却被当成「月份集合」传给
  /// `PieceRecord.isSettled`，导致整月结算在计数页永远显示未结算。
  SettlementState _settlementState = SettlementState.empty;

  /// 工人 id → 工号。流水只存了姓名快照，按工号查找要靠档案补。
  Map<String, String> _workerCodes = const {};

  /// 流水每页条数（10 / 20 / 50），默认 20。
  int _pageSize = Pager.defaultPageSize;

  /// 流水当前页（从 0 开始）。
  ///
  /// 它是**用户态**：改页码、改每页条数、改查找词、换日期都会让它失效。
  /// 所以每次都由 [Pager] 收敛一次，绝不直接拿去当下标。
  int _pageIndex = 0;

  /// 录入时直接标记已结算（默认未结算）。
  bool _settledOnEntry = false;

  /// 业务发生时刻（当天第几分钟）。默认取当前时间，补录可改。
  int _minuteOfDay = AppClock.nowMinuteOfDay();

  /// 是否加班。
  bool _overtime = false;

  /// 用户手动动过加班开关后，就不再让「超时自动预勾」覆盖他的选择。
  bool _overtimeManual = false;

  int _loadedVersion = -1;
  String _loadedDate = '';

  /// 上一次看到的页签下标，用来识别"刚进入计数页"。
  late int _lastTabIndex = widget.selection.tabIndex;

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
    _flowSearch.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    // 重新进入「马上计数」：时刻也要回到当下。
    // 日期由 SelectionState.selectTab 负责重置（那里才知道"从哪切到哪"），
    // 这里只管页面自己的瞬时状态，避免两边互相覆写。
    final tab = widget.selection.tabIndex;
    final entering = tab == SelectionState.countTabIndex &&
        _lastTabIndex != SelectionState.countTabIndex;
    _lastTabIndex = tab;
    if (entering) {
      setState(() {
        _minuteOfDay = AppClock.nowMinuteOfDay();
        // 重新进入后按当前时刻重新判断加班，不继承上次的手动选择
        _overtimeManual = false;
        _syncOvertimeAuto(notify: false);
        // 上一笔记录的主键作废，避免和这次的补录撞车
        _pendingRecordId = null;
      });
    }
    if (_loadedDate != widget.selection.date) {
      // 换了业务日期就是另一批流水：页码必须回到第一页，
      // 否则「昨天在第 4 页、今天只有 1 页」会直接落在空白页上。
      _pageIndex = 0;
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

    // 一次取全量档案：在用的给选择器，全部（含已停用）用来按工号反查流水。
    // 已停用的工人历史账还在，按工号查找时不能查不到。
    final allWorkers = await services.workers.listAll();
    final workers = allWorkers
        .where((worker) => !worker.isArchived)
        .toList(growable: false);
    final toys = await services.toys.listActive();
    final allToys = await services.toys.listAll();
    final records = await services.records.listByDate(date);
    final adjustments = Dates.isValidYmd(date)
        ? await services.adjustments.listRange(
            DateRange(start: date, end: date),
          )
        : const <Adjustment>[];
    final locked = Dates.isValidYmd(date)
        ? await services.months.isLocked(Dates.ymOfYmd(date))
        : false;
    // 结算状态取全库统一快照：整月标记 + 逐笔 settled_at 都在里面。
    // 结算页一标记，这里切页或收到 AppRefresh 就能同步，不再各读各的。
    final settlementState = await services.settlementMarks.loadState();
    if (!mounted) return;
    setState(() {
      _workers = workers;
      _toys = toys;
      _workerCodes = {
        for (final worker in allWorkers) worker.id: worker.code,
      };
      _basePrices = {
        for (final toy in allToys) toy.id: toy.unitPriceTenThousandth,
      };
      _records = records;
      _adjustments = adjustments;
      _settlementState = settlementState;
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
      subtitleOf: (item) => '单价 ${item.priceLabel}',
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
    // 单价先校验。改单价填错时如果先弹「数量要大于 0」，
    // 用户会以为是改单价把数量改坏了，两个字段的提示必须各归各的。
    final price = _effectivePrice;
    if (price == null) {
      showToast(
        context,
        '临时单价格式不对，最多 4 位小数（例：0.035）',
        isError: true,
      );
      return;
    }
    final quantity = _quantityValue;
    if (quantity == null) {
      final raw = Money.normalizeDigits(_quantity.text).trim();
      showToast(
        context,
        raw.isEmpty
            ? '先在「数量」里填这一笔做了多少件（要大于 0）'
            : '数量要填大于 0 的整数',
        isError: true,
      );
      _quantityFocus.requestFocus();
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
        settled: _settledOnEntry,
      );
      _pendingRecordId = null;
      if (!mounted) return;
      _quantity.clear();
      _remark.clear();
      _settledOnEntry = false;
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

  /// 打开调整项录入。[type] 由四个快捷入口决定，[existing] 非空为修改。
  Future<void> _openAdjustment({
    AdjustmentType? type,
    Adjustment? existing,
  }) async {
    final services = _services;
    if (services == null) return;
    if (_locked) {
      showToast(context, '该月已锁账，不能修改调整项', isError: true);
      return;
    }
    if (_workers.isEmpty) {
      showToast(context, '还没有工人档案，请先建档', isError: true);
      return;
    }
    // 改历史调整项时，那个人可能已经被归档（不在 active 列表里），
    // 否则弹窗里选不中他，保存会被「请选择工人」拦住。
    var workers = _workers;
    if (existing != null &&
        !workers.any((worker) => worker.id == existing.workerId)) {
      workers = await services.workers.listAll();
      if (!mounted) return;
    }
    final saved = await showAdjustmentSheet(
      context: context,
      services: services,
      defaultDate: widget.selection.date,
      defaultWorkerId: widget.selection.workerId,
      workers: workers,
      initialType: type ?? AdjustmentType.bonus,
      existing: existing,
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _deleteAdjustment(Adjustment adjustment) async {
    final services = _services;
    if (services == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除这笔${adjustment.type.label}？',
      message: '${adjustment.workerNameSnapshot} · ${adjustment.remark}\n'
          '金额 ${Money.formatCentsSigned(adjustment.signedCents)} 元\n'
          '删除后 30 天内可在回收站恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await services.adjustments.softDelete(adjustment.id);
      services.notifyDataChanged();
      await _reload();
      if (!mounted) return;
      showToast(context, '已移到回收站，30 天内可恢复');
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
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

  /// 是否命中查找条件（姓名 / 工号 / 拼音首字母）。
  ///
  /// 工号从档案表补：流水里只存了姓名快照，没有工号，
  /// 但车间里喊人常用工号（"W012 那笔"），查找必须两种都认。
  bool _matchesFlowQuery(PieceRecord record, String query) {
    if (query.isEmpty) return true;
    return PinyinHelper.matches(
      query: query,
      name: record.workerNameSnapshot,
      initials: PinyinHelper.initialsOf(record.workerNameSnapshot),
      code: _workerCodes[record.workerId] ?? '',
    );
  }

  /// 当前查找条件下的流水（不动原始列表，统计口径也不受影响）。
  List<PieceRecord> get _filteredRecords {
    final query = _flowSearch.text.trim();
    if (query.isEmpty) return _records;
    return _records
        .where((record) => _matchesFlowQuery(record, query))
        .toList(growable: false);
  }

  Pager get _flowPager => Pager.of(
        total: _filteredRecords.length,
        pageSize: _pageSize,
        page: _pageIndex,
      );

  void _clearFlowSearch() {
    _flowSearch.clear();
    setState(() => _pageIndex = 0);
  }

  /// 换每页条数：立即生效，并回到第一页。
  void _changePageSize(int size) {
    if (size == _pageSize) return;
    setState(() {
      _pageSize = size;
      _pageIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worker = _worker;
    final toy = _toy;
    final subtotal = _subtotal;
    final date = widget.selection.date;
    final isToday = date == SelectionState.today;

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
                  subtitle: toy == null
                      ? '单价会自动带出（可临时调价）'
                      : '档案单价 ${toy.priceLabel}',
                  icon: Icons.toys_outlined,
                  onTap: _pickToy,
                  accent: const Color(0xFF7A3E00),
                ),
                const SizedBox(height: 14),
                _buildQuantityCard(theme, subtotal),
                const SizedBox(height: 14),
                _buildSettleRow(theme),
                FilledButton.icon(
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
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 12),
                _buildKeepSwitches(theme),
                const SizedBox(height: 8),
                _buildAdjustmentSection(theme, date),
                const SizedBox(height: 8),
                _buildFlowCard(theme, date),
              ],
            ),
    );
  }

  /// 当天流水：查找（姓名/工号）+ 分页（10/20/50）。
  ///
  /// 为什么要分页而不是全量渲染：一天 200 笔时 ListView 会把 200 行一次性
  /// build 出来，滚动卡、首屏慢，而且往下翻几十屏才能看到最后一条。
  /// 现在只 build 当前页的 10/20/50 行，查找也只在内存里过滤，不动数据库。
  Widget _buildFlowCard(ThemeData theme, String date) {
    final query = _flowSearch.text.trim();
    final filtered = _filteredRecords;
    final pager = _flowPager;
    final rows = pager.slice(filtered);
    // 条数还没超过最小档位时不显示分页条，避免"3 笔流水也显示 1/1 页"的噪音
    final showPager = _records.length > Pager.pageSizes.first || pager.page > 0;

    return SectionCard(
      title: '$date 的流水',
      trailing: Text(
        query.isEmpty
            ? '${_records.length} 笔'
            : '匹配 ${filtered.length}/${_records.length} 笔',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
      ),
      child: _records.isEmpty
          ? const EmptyState(
              title: '这天还没有流水',
              hint: '上面选好工人和工序，填数量就能记一笔',
              icon: Icons.playlist_add,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SearchField(
                  key: const ValueKey('flow-search'),
                  controller: _flowSearch,
                  hintText: '查找：输入工人姓名或工号',
                  onChanged: (_) => setState(() => _pageIndex = 0),
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SearchMatchHint(
                    query: query,
                    text: '匹配到 ${filtered.length} 笔（共 ${_records.length} 笔）',
                    onClear: _clearFlowSearch,
                  ),
                ],
                const SizedBox(height: 4),
                if (filtered.isEmpty)
                  EmptyState(
                    title: '没有匹配的流水',
                    hint: '换个姓名或工号试试，或点「清空」看全部流水',
                    icon: Icons.search_off,
                    action: TextButton(
                      onPressed: _clearFlowSearch,
                      child: const Text('清空查找'),
                    ),
                  )
                else ...[
                  for (var index = 0; index < rows.length; index++) ...[
                    if (index > 0) const Divider(height: 20),
                    _buildRecordRow(theme, rows[index]),
                  ],
                  if (showPager) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 16),
                    _buildPagerBar(theme, pager),
                  ],
                ],
              ],
            ),
    );
  }

  /// 分页条：每页 10 / 20 / 50 + 上一页 / 第 x/y 页 / 下一页。
  ///
  /// 用 Wrap 而不是 Row：超大字号下"每页 + 三个档位 + 翻页"挤不进一行，
  /// 折成两行也比溢出压字好。
  Widget _buildPagerBar(ThemeData theme, Pager pager) {
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted);
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('每页', style: muted),
            for (final size in Pager.pageSizes)
              ChoiceChip(
                key: ValueKey('flow-page-size-$size'),
                label: Text('$size'),
                selected: _pageSize == size,
                onSelected: (_) => _changePageSize(size),
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('flow-page-prev'),
              tooltip: '上一页',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left),
              onPressed: pager.hasPrev
                  ? () => setState(() => _pageIndex = pager.page - 1)
                  : null,
            ),
            Text('第 ${pager.pageNumber}/${pager.pageCount} 页', style: muted),
            IconButton(
              key: const ValueKey('flow-page-next'),
              tooltip: '下一页',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: pager.hasNext
                  ? () => setState(() => _pageIndex = pager.page + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// 补贴 / 计时 / 扣款 / 预支：四个方向各一个入口，当天已录入的逐条列出。
  ///
  /// 放在计数页而不是藏进菜单里，是因为这四项和计件是同一个动作——
  /// 车间里记一笔活的同时顺手记一笔补贴或扣款，不该让人去别处找。
  Widget _buildAdjustmentSection(ThemeData theme, String date) {
    final total =
        _adjustments.fold<int>(0, (sum, item) => sum + item.signedCents);
    return SectionCard(
      title: '补贴 / 计时 / 扣款 / 预支',
      trailing: Text(
        _adjustments.isEmpty ? '暂无' : '合计 ${Money.formatCentsSigned(total)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: total == 0
              ? AppTheme.muted
              : (total > 0 ? AppTheme.success : AppTheme.danger),
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final type in AdjustmentType.values)
                OutlinedButton.icon(
                  onPressed:
                      _locked ? null : () => _openAdjustment(type: type),
                  icon: Icon(_adjustmentIcon(type), size: 20),
                  label: Text(type.label),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor:
                        type.sign > 0 ? AppTheme.success : AppTheme.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_adjustments.isEmpty)
            const MutedText(
              '这天还没有补贴 / 计时 / 扣款 / 预支。点上面的按钮记一笔，'
              '金额会直接进结算和工资条。',
            )
          else
            for (var index = 0; index < _adjustments.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _buildAdjustmentRow(theme, _adjustments[index]),
            ],
        ],
      ),
    );
  }

  IconData _adjustmentIcon(AdjustmentType type) => switch (type) {
        AdjustmentType.bonus => Icons.card_giftcard,
        AdjustmentType.hourly => Icons.timer_outlined,
        AdjustmentType.deduction => Icons.remove_circle_outline,
        AdjustmentType.advance => Icons.payments_outlined,
      };

  Widget _buildAdjustmentRow(ThemeData theme, Adjustment adjustment) {
    final positive = adjustment.signedCents > 0;
    final color = positive ? AppTheme.success : AppTheme.danger;
    return InkWell(
      onTap: _locked ? null : () => _openAdjustment(existing: adjustment),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                adjustment.type.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adjustment.summaryLabel,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  // 人名、时刻、金额挤在一行，超大字号下靠 Wrap 自动折行
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${adjustment.workerNameSnapshot} · '
                        '${adjustment.timeLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppTheme.muted),
                      ),
                      Text(
                        '${Money.formatCentsSigned(adjustment.signedCents)} 元',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SettlementBadge(
                        _settlementState.isAdjustmentSettled(adjustment)
                            ? SettlementStatus.settled
                            : SettlementStatus.unsettled,
                        compact: true,
                      ),
                      if (_isBackfill(adjustment.date, adjustment.createdAt))
                        BackfillBadge(
                          daysEarlier: Dates.daysBetween(
                            adjustment.date,
                            SelectionState.today,
                          ),
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_locked)
              IconButton(
                tooltip: '删除这笔${adjustment.type.label}',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteAdjustment(adjustment),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBar(ThemeData theme, String date, bool isToday) {
    final mutedStyle =
        theme.textTheme.bodyLarge?.copyWith(color: AppTheme.muted);
    final today = SelectionState.today;
    final holiday = CnHolidays.of(date);
    // 早于今天 = 正在补录；晚于今天 = 日期在未来，都值得提醒
    final isBackdate = date.compareTo(today) < 0;
    final isFuture = date.compareTo(today) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.event_outlined, size: 22, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    isToday ? '$date（今天）' : date,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isToday ? AppTheme.primary : AppTheme.danger,
                    ),
                  ),
                  if (holiday != null)
                    HolidayBadge(holiday, compact: true),
                  if (isBackdate)
                    BackfillBadge(
                      daysEarlier: Dates.daysBetween(date, today),
                      compact: true,
                    ),
                  if (isFuture)
                    _miniTag('未来日期', AppTheme.danger),
                ],
              ),
            ),
            if (!isToday)
              TextButton(
                onPressed: () {
                  widget.selection.resetDateToToday();
                  setState(() => _minuteOfDay = AppClock.nowMinuteOfDay());
                },
                child: const Text('回今天'),
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
        if (isBackdate) ...[
          const SizedBox(height: 8),
          InfoBanner(
            text: '正在补录 $date（今天 $today）。保存后这笔账算在 $date，'
                '明细里会标「补录」，统计不会算到今天。',
            color: AppTheme.danger,
            icon: Icons.history,
          ),
        ],
        if (isFuture) ...[
          const SizedBox(height: 8),
          InfoBanner(
            text: '$date 在今天（$today）之后。确认是要预记明天的活吗？',
            color: AppTheme.warning,
            icon: Icons.event_available,
          ),
        ],
      ],
    );
  }

  /// 极小的说明标签（不参与点击）。
  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
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

  /// 档案单价（没开临时调价时实际就用它）。
  int? get _archivePrice => _toy?.unitPriceTenThousandth;

  /// 现在用的是不是「与档案不同」的临时单价。
  bool get _isTempPrice {
    if (!_manualPriceEnabled) return false;
    final price = _effectivePrice;
    final base = _archivePrice;
    if (price == null || base == null) return false;
    return PriceRules.isTemporary(recordUnitPrice: price, baseUnitPrice: base);
  }

  /// 数量输入的问题（只在用户填了内容时提示，避免一进来就红一片）。
  String? get _quantityError {
    final raw = Money.normalizeDigits(_quantity.text).trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) return '要填大于 0 的整数';
    return null;
  }

  /// 临时单价输入的问题。
  String? get _priceError {
    if (!_manualPriceEnabled) return null;
    final raw = _manualPrice.text.trim();
    if (raw.isEmpty) return null;
    return Money.tryParsePrice(raw) == null ? '最多 4 位小数，例：0.035' : null;
  }

  /// 切换「用档案价 / 临时调价」。
  ///
  /// 这里改的只是**这一笔**的单价：保存时写进流水的 `unit_price_snapshot`，
  /// 档案表一动都不动。所以回填时也必须用纯数字——
  /// 早先回填的是带「元」的展示文本，解析必然失败，
  /// 于是出现「改单价却提示数量要大于 0 / 单价格式不对」的怪现象。
  void _toggleManualPrice() {
    setState(() {
      _manualPriceEnabled = !_manualPriceEnabled;
      if (_manualPriceEnabled) {
        final base = _archivePrice;
        _manualPrice.text = base == null ? '' : Money.formatPrice(base);
      }
    });
  }

  Widget _buildQuantityCard(ThemeData theme, int? subtotal) {
    final price = _effectivePrice;
    final base = _archivePrice;
    return SectionCard(
      title: '数量与单价',
      trailing: TextButton.icon(
        onPressed: _toggleManualPrice,
        icon: Icon(
          _manualPriceEnabled ? Icons.restart_alt : Icons.price_change_outlined,
          size: 20,
        ),
        label: Text(_manualPriceEnabled ? '用档案价' : '临时调价'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _quantity,
            focusNode: _quantityFocus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: const TextStyle(fontSize: 36, color: Color(0xFFB6BDC9)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              errorText: _quantityError,
              helperText: _quantityError == null ? '填这一笔做了多少件' : null,
              helperStyle: const TextStyle(fontSize: 13, color: AppTheme.muted),
            ),
          ),
          if (_manualPriceEnabled) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _manualPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: '本次临时单价（最多 4 位小数）',
                errorText: _priceError,
                helperText: _priceError == null ? '补录过去日期时可填当时的价' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  base == null
                      ? '还没有选玩具工序'
                      : '档案单价 ${Money.formatPrice(base)}'
                          '${price == null ? '' : ' · 本次 ${Money.formatPrice(price)}'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isTempPrice) const TempPriceBadge(compact: true),
              ],
            ),
            const SizedBox(height: 8),
            // 防串库：这句话必须显眼，否则有人会以为在这里改就等于改了档案
            const InfoBanner(
              text: '临时调价只对这一笔生效，档案单价不会被改动。'
                  '要永久改价，请到「设置 → 玩具工序」里改。',
              color: TempPriceBadge.color,
              icon: Icons.lock_outline,
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
                            : '${_quantityValue ?? 0} 件 × ${Money.formatPrice(price)}',
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

  /// 录入时的结算状态：默认未结算，想当场结清就直接打开。
  ///
  /// 只写流水自己的 `settled_at`，不影响同一期的其他笔，
  /// 也不会因为这一笔就把整月当成已结算。
  Widget _buildSettleRow(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _settledOnEntry
            ? AppTheme.success.withValues(alpha: 0.08)
            : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _settledOnEntry
              ? AppTheme.success.withValues(alpha: 0.4)
              : const Color(0xFFE6E9EF),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _settledOnEntry ? Icons.check_circle : Icons.schedule,
            color: _settledOnEntry ? AppTheme.success : AppTheme.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _settledOnEntry ? '这一笔：已结算' : '这一笔：未结算',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _settledOnEntry ? AppTheme.success : null,
                  ),
                ),
                Text(
                  _settledOnEntry
                      ? '保存后直接算作已发钱，只影响这一笔'
                      : '默认未结算，发钱后再标记（可整期也可逐笔）',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          Switch(
            // 页面里还有加班、保留工人等开关，给结算这一个稳定的定位键
            key: const ValueKey('count-settle-switch'),
            value: _settledOnEntry,
            onChanged: (value) => setState(() => _settledOnEntry = value),
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
          ? '加班单价 ${pricing.priceLabel}'
          : '单价 ${Money.formatPrice(base)} → ${pricing.priceLabel}'
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

  /// 这条是不是"今天补录的前面日期"。
  bool _isBackfill(String workDate, int createdAt) => BackfillRules.isBackfill(
        workDate: workDate,
        createdAtMillis: createdAt,
        today: SelectionState.today,
      );

  /// 单条流水：两行结构，标签区可折行，杜绝文字堆叠。
  ///
  /// 一行塞「时间 + 工人 + 玩具 + 单价 + 件数 + 金额 + 加班 + 补录」必然挤爆：
  /// 大字号下 Row 里全是无约束的 Text，溢出后就会互相压住。
  /// 现在左栏只放名称（单行截断），右栏只放数值，中间的时间与标签
  /// 全部丢进 Wrap 自动换行——标签再多也只是往下长，不会挤占金额。
  Widget _buildRecordRow(ThemeData theme, PieceRecord record) {
    final backfill = _isBackfill(record.date, record.createdAt);
    final tempPrice = PriceRules.isTemporary(
      recordUnitPrice: record.unitPriceSnapshot,
      baseUnitPrice: _basePrices[record.toyId] ?? 0,
    );
    final settled = _settlementState.isPieceSettled(record);
    final name = '${record.workerNameSnapshot} · ${record.toyNameSnapshot}'
        '${record.processSnapshot == Defaults.defaultProcess ? '' : ' / ${record.processSnapshot}'}';

    return InkWell(
      onTap: _locked ? null : () => _editRecord(record),
      onLongPress: _locked ? null : () => _deleteRecord(record),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.fromLTRB(backfill ? 8 : 0, 6, 0, 6),
        decoration: backfill
            ? BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.05),
                border: const Border(
                  left: BorderSide(color: AppTheme.danger, width: 3),
                ),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主信息：工人 + 玩具/工序，长名称截断
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: backfill ? AppTheme.danger : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 辅助与标签：时间、加班、临时调价、补录、结算状态
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        record.timeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: backfill ? AppTheme.danger : AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (record.overtime)
                        _miniTag(
                          '加班 ×${record.overtimeMultiplierLabel}',
                          AppTheme.warning,
                        ),
                      if (tempPrice) const TempPriceBadge(compact: true),
                      if (backfill)
                        BackfillBadge(
                          daysEarlier: Dates.daysBetween(
                            record.date,
                            SelectionState.today,
                          ),
                          compact: true,
                        ),
                      SettlementBadge(
                        settled
                            ? SettlementStatus.settled
                            : SettlementStatus.unsettled,
                        compact: true,
                      ),
                    ],
                  ),
                  if (record.remark.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '备注：${record.remark}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 数值区限宽 + 等比缩放：金额位数再多也不会把左边压扁
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      Money.formatCents(record.subtotalCents),
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${record.quantity} 件 × ${record.pricingPriceLabel}',
                      maxLines: 1,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted),
                    ),
                  ),
                ],
              ),
            ),
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
