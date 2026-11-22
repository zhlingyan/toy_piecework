import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/failures.dart';
import '../../core/money.dart';
import '../../data/services/backup_service.dart';
import '../../services/app_services.dart';
import '../archives/toys_page.dart';
import '../archives/workers_page.dart';
import '../common/ui_kit.dart';
import '../reports/annual_page.dart';
import '../theme.dart';
import '../trash/trash_page.dart';
import 'cloud_backup_page.dart';
import 'restore_flow.dart';

/// 设置：档案管理、本地备份恢复、旧账导入、回收站、录入习惯。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _workerCount = 0;
  int _toyCount = 0;
  int _trashCount = 0;
  bool _busy = false;
  int _loadedVersion = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (_loadedVersion != services.refresh.version) {
      _loadedVersion = services.refresh.version;
      _load();
    }
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final workers = await services.workers.listActive();
    final toys = await services.toys.listActive();
    final trashRecords = await services.records.listTrash();
    final trashAdjustments = await services.adjustments.listTrash();
    if (!mounted) return;
    setState(() {
      _workerCount = workers.length;
      _toyCount = toys.length;
      _trashCount = trashRecords.length + trashAdjustments.length;
    });
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final includeExpired = await _askIncludeExpired();
      if (includeExpired == null) return;
      final json = await services.backup.buildJson(includeExpiredDeleted: includeExpired);
      final uri = await services.files.exportText(
        json,
        BackupService.buildFileName(),
      );
      if (!mounted) return;
      showToast(
        context,
        uri == null ? '已取消保存' : '备份已保存：${uri.pathSegments.isEmpty ? uri : uri.pathSegments.last}',
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '备份失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _askIncludeExpired() async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导出本地备份'),
        content: const Text(
          '默认不包含「删除已超过 30 天」的记录。\n\n'
          '如果要把整本账（含历史删改痕迹）完整留档，可以选择包含。',
          style: TextStyle(fontSize: 17, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('包含超期删除项'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('按默认导出'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final text = await services.files.pickTextFile();
      if (text == null) return;
      if (!mounted) return;
      final restored = await restoreFromBackupText(
        context,
        services: services,
        text: text,
        sourceLabel: '本地备份文件',
      );
      if (restored) await _load();
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '恢复失败，已回滚原账：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLegacy() async {
    if (_busy) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final text = await services.files.pickTextFile();
      if (text == null) return;
      final preview = await services.legacy.inspect(text);
      if (!mounted) return;

      final ok = await showConfirmDialog(
        context,
        title: '导入微信小程序旧账？',
        message: '日期范围：${preview.rangeLabel}\n'
            '可导入 ${preview.willImport} 笔'
            '${preview.skippedExisting > 0 ? '，已存在 ${preview.skippedExisting} 笔会跳过' : ''}'
            '${preview.skippedLocked > 0 ? '，${preview.skippedLocked} 笔因月份锁账跳过' : ''}'
            '${preview.skippedInvalid > 0 ? '，${preview.skippedInvalid} 条数据不完整会跳过' : ''}\n\n'
            '缺失的工人/玩具会自动建档并设为停用状态；重复导入不会产生重复流水。',
        confirmText: '开始导入',
      );
      if (!ok) return;

      final result = await services.legacy.import(text);
      services.notifyDataChanged();
      if (!mounted) return;
      showToast(
        context,
        '导入完成：新增 ${result.inserted} 笔，跳过 ${result.skippedExisting} 笔，'
        '自动建档 ${result.createdWorkers} 人 / ${result.createdToys} 项',
      );
      await _load();
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '导入失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: false,
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          SectionCard(
            title: '显示与字号',
            child: AnimatedBuilder(
              animation: services.settings,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _fontChoice(services, '标准', Defaults.fontScaleStandard),
                      _fontChoice(services, '大', Defaults.fontScaleLarge),
                      _fontChoice(services, '超大', Defaults.fontScaleHuge),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MutedText('选完立即生效，不用重启。字大了以后每页都会自动重排，不会挤成一行。'),
                ],
              ),
            ),
          ),
          SectionCard(
            title: '加班',
            child: AnimatedBuilder(
              animation: services.settings,
              builder: (context, _) {
                final settings = services.settings;
                final byMultiplier =
                    settings.overtimeMode == OvertimeMode.multiplier;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MutedText('加班费怎么算'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('按倍数乘'),
                          selected: byMultiplier,
                          onSelected: (_) => settings
                              .setOvertimeMode(OvertimeMode.multiplier),
                        ),
                        ChoiceChip(
                          label: const Text('按玩具加班单价'),
                          selected: !byMultiplier,
                          onSelected: (_) =>
                              settings.setOvertimeMode(OvertimeMode.unitPrice),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (byMultiplier) ...[
                      MutedText('加班倍率'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final perMille in const [1200, 1500, 1800, 2000])
                            ChoiceChip(
                              label: Text('×${Money.formatMultiplier(perMille)}'),
                              selected:
                                  settings.overtimeMultiplierPerMille == perMille,
                              onSelected: (_) => settings
                                  .setOvertimeMultiplierPerMille(perMille),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      MutedText(
                        '例：正常单价 0.20 元，加班按 '
                        '×${Money.formatMultiplier(settings.overtimeMultiplierPerMille)}'
                        ' 就是 '
                        '${Money.formatPrice(Money.applyMultiplier(2000, settings.overtimeMultiplierPerMille))}'
                        ' 元/件。',
                      ),
                    ] else
                      MutedText(
                        '每个玩具的加班单价到「玩具与工序」里单独填。'
                        '没填的玩具会自动按 ×'
                        '${Money.formatMultiplier(settings.overtimeMultiplierPerMille)}'
                        ' 兜底，不会算成白干。',
                      ),
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.overtimeAutoDetect,
                      onChanged: settings.setOvertimeAutoDetect,
                      title: const Text('过了下班时间自动标记加班'),
                      subtitle: const Text('只是帮你预先勾上，随时能改回来'),
                    ),
                    if (settings.overtimeAutoDetect)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('正常下班时间'),
                        subtitle: Text(
                          '晚于 ${Dates.hhmm(settings.workEndMinute)} 录入的自动算加班',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: settings.workEndMinute ~/ 60,
                                minute: settings.workEndMinute % 60,
                              ),
                              helpText: '正常几点下班？',
                            );
                            if (picked == null) return;
                            await settings
                                .setWorkEndMinute(picked.hour * 60 + picked.minute);
                          },
                          child: const Text('修改'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SectionCard(
            title: '档案管理',
            child: Column(
              children: [
                _buildTile(
                  icon: Icons.people_outline,
                  title: '工人档案',
                  subtitle: '$_workerCount 位在用 · 支持同名与拼音搜索',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WorkersPage()),
                    );
                    services.notifyDataChanged();
                  },
                ),
                const Divider(height: 1),
                _buildTile(
                  icon: Icons.toys_outlined,
                  title: '玩具与工序',
                  subtitle: '$_toyCount 项在用 · 单价最高 4 位小数',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ToysPage()),
                    );
                    services.notifyDataChanged();
                  },
                ),
              ],
            ),
          ),
          SectionCard(
            title: '报表',
            child: _buildTile(
              icon: Icons.bar_chart_outlined,
              title: '年度报表',
              subtitle: '按年汇总每人产量与工资，可导出 CSV',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnnualPage()),
              ),
            ),
          ),
          SectionCard(
            title: '数据与备份',
            child: Column(
              children: [
                _buildTile(
                  icon: Icons.save_alt,
                  title: '导出本地备份',
                  subtitle: '打包整本账为 JSON，存到手机任意目录',
                  onTap: _exportBackup,
                ),
                const Divider(height: 1),
                _buildTile(
                  icon: Icons.settings_backup_restore,
                  title: '从备份恢复',
                  subtitle: '先校验再预览，恢复前自动备份当前账本',
                  onTap: _restoreBackup,
                ),
                const Divider(height: 1),
                ListenableBuilder(
                  listenable: services.settings,
                  builder: (context, _) => _buildTile(
                    icon: Icons.cloud_outlined,
                    title: '云端备份',
                    subtitle: _cloudSubtitle(services),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CloudBackupPage(),
                        ),
                      );
                      services.notifyDataChanged();
                    },
                  ),
                ),
                const Divider(height: 1),
                _buildTile(
                  icon: Icons.file_download_outlined,
                  title: '导入微信小程序旧账',
                  subtitle: '按原 ID 去重，重复导入不会多记',
                  onTap: _importLegacy,
                ),
                const Divider(height: 1),
                _buildTile(
                  icon: Icons.restore_from_trash_outlined,
                  title: '回收站',
                  subtitle: _trashCount == 0 ? '暂无删除记录' : '$_trashCount 条待处理',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TrashPage()),
                    );
                    services.notifyDataChanged();
                  },
                ),
              ],
            ),
          ),
          SectionCard(
            title: '录入习惯',
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: AnimatedBuilder(
              animation: services.settings,
              builder: (context, _) => Column(
                children: [
                  SwitchListTile(
                    value: services.settings.keepWorker,
                    onChanged: (value) => services.settings.setKeepWorker(value),
                    title: const Text('连录时保留工人'),
                    subtitle: const Text('关掉后每笔都要重新选人', style: TextStyle(fontSize: 14)),
                  ),
                  SwitchListTile(
                    value: services.settings.keepToy,
                    onChanged: (value) => services.settings.setKeepToy(value),
                    title: const Text('连录时保留工序'),
                    subtitle: const Text('关掉后每笔都要重新选货', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
          SectionCard(
            title: '关于',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('玩具厂计件计数与工资结算', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                const MutedText(
                  '本地优先：所有记账、查询、结算都在手机上完成，断网也能用。'
                  '金额全程按整数计算（单价万分之一元、小计按分），逐笔取整后合计。',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.offline_bolt_outlined, size: 18, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Text('离线可用', style: theme.textTheme.bodyMedium),
                    const SizedBox(width: 16),
                    const Icon(Icons.lock_outline, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text('数据只存本机', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _cloudSubtitle(AppServices services) {
    final settings = services.settings;
    if (!settings.cloudAutoEnabled) return '未开启自动备份 · 支持坚果云等 WebDAV';
    final last = settings.lastCloudBackupAt;
    if (last == null) return '自动备份已开启 · 还没成功备份过';
    final time = DateTime.fromMillisecondsSinceEpoch(last);
    String two(int value) => value.toString().padLeft(2, '0');
    return '自动备份已开启 · 上次 '
        '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  Widget _fontChoice(AppServices services, String label, double scale) {
    final selected = services.settings.fontScale == scale;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => services.settings.setFontScale(scale),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
        child: Icon(icon, size: 22, color: AppTheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 14, color: AppTheme.muted)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
      onTap: _busy ? null : onTap,
    );
  }
}
