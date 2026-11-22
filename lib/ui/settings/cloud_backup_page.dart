import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../data/services/cloud_backup_service.dart';
import '../../services/app_services.dart';
import '../common/ui_kit.dart';
import '../theme.dart';
import 'restore_flow.dart';

/// 云备份设置：坚果云（或任意 WebDAV）账号、自动备份开关、立即备份、云端恢复。
class CloudBackupPage extends StatefulWidget {
  const CloudBackupPage({super.key});

  @override
  State<CloudBackupPage> createState() => _CloudBackupPageState();
}

class _CloudBackupPageState extends State<CloudBackupPage> {
  final _url = TextEditingController(text: Defaults.jianguoyunUrl);
  final _folder = TextEditingController(text: Defaults.cloudBackupDir);
  final _user = TextEditingController();
  final _password = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _obscure = true;
  String? _statusLine;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _url.dispose();
    _folder.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final services = AppScope.read(context);
    final config = await services.cloud.loadConfig();
    if (!mounted) return;
    setState(() {
      if (config != null) {
        _url.text = config.normalizedBaseUrl;
        _folder.text = config.normalizedFolder;
        _user.text = config.username;
        _password.text = config.password;
      }
      _loading = false;
    });
  }

  CloudConfig? _readConfig() {
    final url = _url.text.trim();
    final user = _user.text.trim();
    final password = _password.text;
    if (url.isEmpty) {
      showToast(context, '请填写 WebDAV 地址', isError: true);
      return null;
    }
    if (!url.startsWith('http')) {
      showToast(context, '地址要以 https:// 开头', isError: true);
      return null;
    }
    if (user.isEmpty) {
      showToast(context, '请填写登录账号', isError: true);
      return null;
    }
    if (password.isEmpty) {
      showToast(context, '请填写应用密码', isError: true);
      return null;
    }
    return CloudConfig(
      baseUrl: url,
      folder: _folder.text,
      username: user,
      password: password,
    );
  }

  Future<void> _saveAndTest() async {
    if (_busy) return;
    final config = _readConfig();
    if (config == null) return;
    final services = AppScope.read(context);
    setState(() {
      _busy = true;
      _statusLine = '正在连接…';
    });
    try {
      await services.cloud.testConnection(config);
      await services.cloud.saveConfig(config);
      if (!mounted) return;
      setState(() => _statusLine = '连接成功，账号已保存');
      showToast(context, '连接成功');
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _statusLine = null);
      showToast(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() async {
    if (_busy) return;
    final services = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final file = await services.cloud.backupNow();
      await services.settings.markCloudBackupSuccess();
      await services.cloud.cleanupAutoBackups();
      if (!mounted) return;
      showToast(context, '已备份到云端：${file.name}');
    } on AppFailure catch (error) {
      await services.settings.markCloudBackupFailure(error.message);
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      await services.settings.markCloudBackupFailure('$error');
      if (!mounted) return;
      showToast(context, '备份失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromCloud() async {
    if (_busy) return;
    final services = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final files = await services.cloud.listBackups();
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() => _busy = false);
        showToast(context, '云端还没有备份文件', isError: true);
        return;
      }
      final picked = await _pickCloudFile(files);
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final text = await services.cloud.downloadBackup(picked.name);
      if (!mounted) return;
      final restored = await restoreFromBackupText(
        context,
        services: services,
        text: text,
        sourceLabel: '云端 ${picked.name}',
      );
      if (restored) {
        await services.settings.markCloudBackupSuccess();
      }
    } on AppFailure catch (error) {
      if (!mounted) return;
      showToast(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '云端恢复失败，本地账本未改动：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CloudFileInfo?> _pickCloudFile(List<CloudFileInfo> files) {
    return showModalBottomSheet<CloudFileInfo>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '选择要恢复的云端备份',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MutedText(
                    '共 ${files.length} 份。自动备份只保留最近 ${Limits.cloudAutoBackupKeep} 份，手动备份不会自动清理。',
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        leading: Icon(
                          file.isAuto
                              ? Icons.autorenew
                              : Icons.bookmark_outline,
                          color: file.isAuto
                              ? AppTheme.muted
                              : AppTheme.primary,
                        ),
                        title: Text(
                          file.name,
                          style: const TextStyle(fontSize: 15),
                        ),
                        subtitle: Text(
                          '${_formatTime(file.modifiedAt)} · ${file.sizeLabel}'
                          '${file.isAuto ? ' · 自动' : ' · 手动'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.muted,
                          ),
                        ),
                        onTap: () => Navigator.of(sheetContext).pop(file),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '时间未知';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _formatLocalTime(int? millis) {
    if (millis == null) return '从未备份';
    return _formatTime(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    final settings = services.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云备份'),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                AnimatedBuilder(
                  animation: settings,
                  builder: (context, _) => SectionCard(
                    title: '备份状态',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyValueRow(
                          label: '上次成功',
                          value: _formatLocalTime(settings.lastCloudBackupAt),
                        ),
                        if (settings.lastCloudBackupError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InfoBanner(
                              icon: Icons.error_outline,
                              color: AppTheme.danger,
                              text: '上次失败：${settings.lastCloudBackupError}',
                            ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.cloudAutoEnabled,
                          onChanged: (value) async {
                            if (value && !await _hasConfig(services)) return;
                            await settings.setCloudAutoEnabled(value);
                          },
                          title: const Text('自动备份'),
                          subtitle: const Text(
                            '打开应用或切回前台时检查，距上次超过 24 小时且有新数据才上传',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _backupNow,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('立即备份'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _restoreFromCloud,
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('从云端恢复'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SectionCard(
                  title: '账号设置',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'WebDAV 地址',
                          hintText: Defaults.jianguoyunUrl,
                          helperText: '坚果云默认地址，注意以 / 结尾',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _user,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: '账号',
                          hintText: '坚果云登录邮箱',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: '应用密码',
                          helperText: '坚果云要在「账户信息 → 安全选项 → 添加应用」生成，'
                              '不是登录密码',
                          helperMaxLines: 3,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _folder,
                        decoration: const InputDecoration(
                          labelText: '云端目录',
                          helperText: '备份文件会放在这个目录里，不存在会自动创建',
                        ),
                      ),
                      if (_statusLine != null) ...[
                        const SizedBox(height: 10),
                        MutedText(_statusLine!),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _saveAndTest,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('保存并测试连接'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '说明',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MutedText(
                        '· 记账、查询、结算全程离线，云端只做异地留档；'
                        '网络不通不影响任何本地操作。',
                      ),
                      const SizedBox(height: 6),
                      const MutedText(
                        '· 自动备份只在前台触发，不用后台定时器，'
                        '不会因为系统清理而失效。',
                      ),
                      const SizedBox(height: 6),
                      const MutedText(
                        '· 云端只保留最近 ${Limits.cloudAutoBackupKeep} 份自动备份，'
                        '「立即备份」生成的手动备份不会被自动删除。',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '账号与应用密码只存在系统安全存储里，不写入账本文件',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<bool> _hasConfig(AppServices services) async {
    final config = await services.cloud.loadConfig();
    if (config != null) return true;
    if (!mounted) return false;
    showToast(context, '请先填写并保存云盘账号', isError: true);
    return false;
  }
}
