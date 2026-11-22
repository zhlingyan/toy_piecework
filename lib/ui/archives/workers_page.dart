import 'package:material_ui/material_ui.dart';

import '../../core/failures.dart';
import '../../data/models/worker.dart';
import '../../domain/pinyin/pinyin_helper.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';
import 'worker_profile_page.dart';

/// 工人档案：支持同名工人（靠编号区分）、归档/启用、拼音首字母手动修正。
class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  List<Worker> _workers = const [];
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
    final workers = await services.workers.listAll();
    if (!mounted) return;
    setState(() {
      _workers = workers;
      _loading = false;
    });
  }

  List<Worker> get _visible {
    return _workers.where((worker) {
      if (!_showArchived && worker.isArchived) return false;
      return PinyinHelper.matches(
        query: _query,
        name: worker.name,
        initials: worker.pinyinInitials,
        code: worker.code,
      );
    }).toList(growable: false);
  }

  Future<void> _openEditor({Worker? worker}) async {
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
        child: _WorkerEditor(services: services, worker: worker),
      ),
    );
    if (saved == true) {
      services.notifyDataChanged();
      await _load();
    }
  }

  /// 打开员工档案；在档案页点「编辑」会回传 'edit'，再打开编辑面板。
  Future<void> _openProfile(Worker worker) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WorkerProfilePage(worker: worker),
      ),
    );
    if (!mounted) return;
    if (result == 'edit') {
      await _openEditor(worker: worker);
    } else {
      await _load();
    }
  }

  Future<void> _toggleArchive(Worker worker) async {
    final services = AppScope.read(context);
    final archive = !worker.isArchived;
    final ok = await showConfirmDialog(
      context,
      title: archive ? '停用 ${worker.name}？' : '重新启用 ${worker.name}？',
      message: archive
          ? '停用后录入页不再显示该工人，但历史流水、结算和报表都能照常查到。'
          : '启用后该工人会重新出现在录入页的选择列表里。',
      confirmText: archive ? '停用' : '启用',
    );
    if (!ok) return;
    await services.workers.setArchived(worker.id, archive);
    services.notifyDataChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final grouped = PinyinHelper.groupByInitial<Worker>(
      visible,
      initialsOf: (worker) => worker.pinyinInitials,
      codeOf: (worker) => worker.code,
      nameOf: (worker) => worker.name,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('工人档案'),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1),
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
                      hintText: '搜姓名 / 首字母 / 编号，如 zs',
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
                          '共 ${_workers.where((w) => !w.isArchived).length} 位在用，'
                          '${_workers.where((w) => w.isArchived).length} 位已停用',
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
                          title: '还没有工人档案',
                          hint: '点右上角「新增」，输入姓名即可',
                          icon: Icons.people_outline,
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
                              for (final worker in entry.value)
                                _buildTile(theme, worker),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTile(ThemeData theme, Worker worker) {
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
          backgroundColor: worker.isArchived
              ? const Color(0xFFEDEFF3)
              : AppTheme.primary.withValues(alpha: 0.1),
          child: Text(
            worker.pinyinInitials.isEmpty ? '?' : worker.pinyinInitials.characters.first,
            style: TextStyle(
              color: worker.isArchived ? AppTheme.muted : AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(worker.name, style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              worker.code,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
            if (worker.isArchived) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEFF3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('已停用', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '首字母 ${worker.pinyinInitials.isEmpty ? '—' : worker.pinyinInitials} · 点一下看档案',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _toggleArchive(worker),
              child: Text(
                worker.isArchived ? '启用' : '停用',
                style: TextStyle(
                  color: worker.isArchived ? AppTheme.success : AppTheme.muted,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
          ],
        ),
        onTap: () => _openProfile(worker),
        ),
      ),
    );
  }
}

class _WorkerEditor extends StatefulWidget {
  const _WorkerEditor({required this.services, this.worker});

  final AppServices services;
  final Worker? worker;

  @override
  State<_WorkerEditor> createState() => _WorkerEditorState();
}

class _WorkerEditorState extends State<_WorkerEditor> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _initials;

  bool _initialsTouched = false;
  bool _saving = false;
  String? _hintCode;

  bool get _isEdit => widget.worker != null;

  @override
  void initState() {
    super.initState();
    final worker = widget.worker;
    _name = TextEditingController(text: worker?.name ?? '')
      ..addListener(_syncInitials);
    _code = TextEditingController(text: worker?.code ?? '');
    _initials = TextEditingController(text: worker?.pinyinInitials ?? '')
      ..addListener(() {
        if (!_initialsTouched) return;
      });
    if (!_isEdit) {
      widget.services.workers.nextCode().then((code) {
        if (!mounted) return;
        setState(() {
          _hintCode = code;
          if (_code.text.isEmpty) _code.text = code;
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _initials.dispose();
    super.dispose();
  }

  void _syncInitials() {
    if (_initialsTouched) return;
    final initials = PinyinHelper.initialsOf(_name.text);
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
      showToast(context, '请填写姓名', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final worker = widget.worker;
      if (worker == null) {
        await widget.services.workers.create(
          name: _name.text,
          code: _code.text,
          pinyinInitials: _initials.text,
        );
      } else {
        // 编号固定不变，避免历史单据对不上人
        await widget.services.workers.update(
          worker.copyWith(
            name: _name.text,
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
            Text(_isEdit ? '修改工人档案' : '新增工人', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: '姓名',
                hintText: '允许同名，用编号区分',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              readOnly: _isEdit,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: '编号',
                hintText: _hintCode == null ? null : '自动生成 $_hintCode',
                helperText: _isEdit ? '编号创建后固定不变，避免历史单据对不上人' : '可改成厂里已有的工号',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _initials,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: '拼音首字母',
                helperText: '自动生成；多音姓氏（单/曾/解/查/仇/区…）可在这里手动改',
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
