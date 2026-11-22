import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/models/toy.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 玩具与工序档案：一个「玩具 + 工序」组合一条档案，各自带单价。
class ToysPage extends StatefulWidget {
  const ToysPage({super.key});

  @override
  State<ToysPage> createState() => _ToysPageState();
}

class _ToysPageState extends State<ToysPage> {
  List<Toy> _toys = const [];
  String _query = '';
  bool _showArchived = false;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final toys = await services.toys.listAll();
    if (!mounted) return;
    setState(() {
      _toys = toys;
      _loading = false;
    });
  }

  List<Toy> get _visible {
    return _toys.where((toy) {
      if (!_showArchived && toy.isArchived) return false;
      return PinyinHelper.matches(
        query: _query,
        name: toy.displayName,
        initials: toy.pinyinInitials,
      );
    }).toList(growable: false);
  }

  Future<void> _openEditor({Toy? toy}) async {
    final services = AppScope.read(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _ToyEditor(services: services, toy: toy),
      ),
    );
    if (saved == true) {
      services.notifyDataChanged();
      await _load();
    }
  }

  Future<void> _toggleArchive(Toy toy) async {
    final services = AppScope.read(context);
    final archive = !toy.isArchived;
    final ok = await showConfirmDialog(
      context,
      title: archive ? '停用「${toy.displayName}」？' : '重新启用「${toy.displayName}」？',
      message: archive
          ? '停用后录入页不再显示该工序，但历史流水与报表仍按原单价快照统计。'
          : '启用后会重新出现在录入页的选择列表里。',
      confirmText: archive ? '停用' : '启用',
    );
    if (!ok) return;
    await services.toys.setArchived(toy.id, archive);
    services.notifyDataChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final grouped = PinyinHelper.groupByInitial<Toy>(
      visible,
      initialsOf: (toy) => toy.pinyinInitials,
      codeOf: (toy) => toy.name,
      nameOf: (toy) => toy.process,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('玩具与工序'),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('新增'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: '搜玩具名 / 工序 / 首字母',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '一个「玩具 + 工序」一条档案，各自记单价',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.muted),
                        ),
                      ),
                      FilterChip(
                        label: const Text('显示已停用'),
                        selected: _showArchived,
                        onSelected: (value) => setState(() => _showArchived = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: visible.isEmpty
                      ? const EmptyState(
                          title: '还没有玩具工序档案',
                          hint: '点右上角「新增」，填玩具名、工序与单价',
                          icon: Icons.toys_outlined,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            for (final entry in grouped.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 10, bottom: 4),
                                child: Text(
                                  entry.key,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              for (final toy in entry.value) _buildTile(theme, toy),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTile(ThemeData theme, Toy toy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE6E9EF)),
        ),
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: toy.isArchived
              ? const Color(0xFFEDEFF3)
              : const Color(0xFF7A3E00).withValues(alpha: 0.1),
          child: Icon(
            Icons.toys_outlined,
            size: 22,
            color: toy.isArchived ? AppTheme.muted : const Color(0xFF7A3E00),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                toy.name,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                toy.process,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
              ),
            ),
            if (toy.isArchived) ...[
              const SizedBox(width: 6),
              const Text('已停用', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
            ],
          ],
        ),
        subtitle: Text(
          '单价 ${toy.priceLabel} 元'
          '${toy.hasOvertimePrice ? ' · 加班 ${toy.overtimePriceLabel} 元' : ''}'
          ' · 首字母 ${toy.pinyinInitials.isEmpty ? '—' : toy.pinyinInitials}',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _toggleArchive(toy),
              child: Text(
                toy.isArchived ? '启用' : '停用',
                style: TextStyle(
                  color: toy.isArchived ? AppTheme.success : AppTheme.muted,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
          ],
        ),
        onTap: () => _openEditor(toy: toy),
        ),
      ),
    );
  }
}

class _ToyEditor extends StatefulWidget {
  const _ToyEditor({required this.services, this.toy});

  final AppServices services;
  final Toy? toy;

  @override
  State<_ToyEditor> createState() => _ToyEditorState();
}

class _ToyEditorState extends State<_ToyEditor> {
  late final TextEditingController _name;
  late final TextEditingController _process;
  late final TextEditingController _price;
  late final TextEditingController _overtimePrice;
  late final TextEditingController _initials;

  bool _saving = false;
  bool _initialsTouched = false;

  bool get _isEdit => widget.toy != null;

  @override
  void initState() {
    super.initState();
    final toy = widget.toy;
    _name = TextEditingController(text: toy?.name ?? '')
      ..addListener(_syncInitials);
    _process = TextEditingController(text: toy?.process ?? Defaults.defaultProcess)
      ..addListener(_syncInitials);
    _price = TextEditingController(
      text: toy == null ? '' : Money.formatPrice(toy.unitPriceTenThousandth),
    );
    _overtimePrice = TextEditingController(
      text: toy == null || !toy.hasOvertimePrice
          ? ''
          : Money.formatPrice(toy.overtimePriceTenThousandth),
    );
    _initials = TextEditingController(text: toy?.pinyinInitials ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _process.dispose();
    _price.dispose();
    _overtimePrice.dispose();
    _initials.dispose();
    super.dispose();
  }

  void _syncInitials() {
    if (_initialsTouched) return;
    final initials = PinyinHelper.initialsOf('${_name.text}${_process.text}');
    if (_initials.text != initials) {
      _initials.value = TextEditingValue(
        text: initials,
        selection: TextSelection.collapsed(offset: initials.length),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      showToast(context, '请填写玩具名称', isError: true);
      return;
    }
    final price = Money.tryParsePrice(_price.text);
    if (price == null) {
      showToast(context, '单价格式不对，最多 4 位小数，如 0.035', isError: true);
      return;
    }
    // 加班单价留空 = 不单独设置，加班时按倍率兜底
    int overtimePrice = 0;
    if (_overtimePrice.text.trim().isNotEmpty) {
      final parsed = Money.tryParsePrice(_overtimePrice.text);
      if (parsed == null) {
        showToast(context, '加班单价格式不对，最多 4 位小数', isError: true);
        return;
      }
      overtimePrice = parsed;
    }
    setState(() => _saving = true);
    try {
      final toy = widget.toy;
      if (toy == null) {
        await widget.services.toys.create(
          name: _name.text,
          process: _process.text,
          unitPriceTenThousandth: price,
          overtimePriceTenThousandth: overtimePrice,
          pinyinInitials: _initials.text,
        );
      } else {
        await widget.services.toys.update(
          toy.copyWith(
            name: _name.text,
            process: _process.text,
            unitPriceTenThousandth: price,
            overtimePriceTenThousandth: overtimePrice,
            pinyinInitials: _initials.text,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(_isEdit ? '修改玩具工序' : '新增玩具工序', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: '玩具名称',
                hintText: '如：小熊挂件',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _process,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: '工序',
                hintText: '默认「整件」，也可填：缝头 / 装眼 / 打包',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: '单价（元）',
                hintText: '如 0.035',
                helperText: '最多 4 位小数。调价只影响以后录入，历史按原单价快照计算',
                suffixText: '元',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _overtimePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: '加班单价（元，可不填）',
                hintText: '留空则按倍率算',
                helperText: '设置里选「按玩具加班单价」时用这个价；留空自动回退到倍率',
                suffixText: '元',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _initials,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: '拼音首字母',
                helperText: '自动生成，可手动修正',
              ),
              onChanged: (_) => setState(() => _initialsTouched = true),
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
              label: Text(_saving ? '正在保存…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}
