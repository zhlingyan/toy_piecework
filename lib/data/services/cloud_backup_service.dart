import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../core/clock.dart';
import '../../core/constants.dart';
import '../../core/failures.dart';
import '../db/app_database.dart';
import 'backup_service.dart';

/// 云备份账号配置。密码只存系统安全存储，不进 SharedPreferences。
class CloudConfig {
  const CloudConfig({
    required this.baseUrl,
    required this.folder,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String folder;
  final String username;
  final String password;

  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  String get normalizedFolder {
    final trimmed = folder.trim();
    if (trimmed.isEmpty) return Defaults.cloudBackupDir;
    return trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  /// 云端目录的绝对路径（相对 WebDAV 根）。
  String get rootPath {
    final segments = normalizedFolder
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '$normalizedBaseUrl$segments';
  }

  String get displayTarget => '$normalizedBaseUrl$normalizedFolder/';

  CloudConfig copyWith({
    String? baseUrl,
    String? folder,
    String? username,
    String? password,
  }) {
    return CloudConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      folder: folder ?? this.folder,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

/// 云端的一份备份文件。
class CloudFileInfo {
  const CloudFileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.isAuto,
  });

  final String name;
  final String path;
  final int size;
  final DateTime? modifiedAt;

  /// 是否为自动备份（滚动清理只删这类）。
  final bool isAuto;

  String get sizeLabel {
    if (size <= 0) return '—';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 自动备份的判定结果，供设置页展示「为什么没有上传」。
enum AutoBackupStatus {
  /// 未开启自动备份。
  disabled,

  /// 没有配置云盘账号。
  noConfig,

  /// 距上次成功备份不足 24 小时。
  notDue,

  /// 本地没有新改动，不必重复上传。
  noChanges,

  /// 已成功上传。
  uploaded,

  /// 上传失败（网络/账号/配额）。
  failed,
}

class AutoBackupResult {
  const AutoBackupResult(this.status, {this.fileName, this.message});

  final AutoBackupStatus status;
  final String? fileName;
  final String? message;

  bool get isUploaded => status == AutoBackupStatus.uploaded;

  /// 设置页展示文案。
  String get description {
    switch (status) {
      case AutoBackupStatus.disabled:
        return '自动备份未开启';
      case AutoBackupStatus.noConfig:
        return '尚未配置云盘账号';
      case AutoBackupStatus.notDue:
        return '距上次备份不足 24 小时，稍后再试';
      case AutoBackupStatus.noChanges:
        return '本地没有新改动，无需上传';
      case AutoBackupStatus.uploaded:
        return '已备份到云端：$fileName';
      case AutoBackupStatus.failed:
        return message ?? '备份失败';
    }
  }
}

/// WebDAV 云备份（默认坚果云）。
///
/// 设计要点：
/// * 所有网络调用都发生在**前台**——应用启动/回到前台时触发一次，
///   不用后台定时器，避免被系统清理、也不消耗额外电量；
/// * 任何云上失败都不影响本地记账：异常一律被捕获并转成中文提示；
/// * 云端只保留最近 30 份**自动**备份，手动备份永不自动删除。
class CloudBackupService {
  CloudBackupService(this._db, this._backup, this._lastSuccessAt);

  final AppDatabase _db;
  final BackupService _backup;

  /// 上次成功备份时间（毫秒）读取器，由调用方注入，避免数据层反向依赖设置对象。
  final int? Function() _lastSuccessAt;

  int? get _lastSuccess => _lastSuccessAt();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _kBaseUrl = 'cloud_base_url';
  static const String _kFolder = 'cloud_folder';
  static const String _kUser = 'cloud_user';
  static const String _kPassword = 'cloud_password';

  static const String autoPrefix = 'toy_piecework_auto';
  static const String manualPrefix = 'toy_piecework_manual';

  static const int _connectTimeoutMs = 12000;
  static const int _receiveTimeoutMs = 40000;

  // ---------------- 账号配置 ----------------

  Future<CloudConfig?> loadConfig() async {
    try {
      final baseUrl = await _storage.read(key: _kBaseUrl);
      final user = await _storage.read(key: _kUser);
      final password = await _storage.read(key: _kPassword);
      if (baseUrl == null || baseUrl.isEmpty || user == null || user.isEmpty) {
        return null;
      }
      if (password == null || password.isEmpty) return null;
      final folder = await _storage.read(key: _kFolder);
      return CloudConfig(
        baseUrl: baseUrl,
        folder: folder ?? Defaults.cloudBackupDir,
        username: user,
        password: password,
      );
    } catch (_) {
      // 安全存储不可用（例如系统升级后密钥失效）时按「未配置」处理
      return null;
    }
  }

  Future<void> saveConfig(CloudConfig config) async {
    await _storage.write(key: _kBaseUrl, value: config.normalizedBaseUrl);
    await _storage.write(key: _kFolder, value: config.normalizedFolder);
    await _storage.write(key: _kUser, value: config.username);
    await _storage.write(key: _kPassword, value: config.password);
  }

  Future<void> clearConfig() async {
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kFolder);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPassword);
  }

  // ---------------- 连接 ----------------

  webdav.Client _client(CloudConfig config) {
    final client = webdav.newClient(
      config.normalizedBaseUrl,
      user: config.username,
      password: config.password,
    );
    client.setConnectTimeout(_connectTimeoutMs);
    client.setReceiveTimeout(_receiveTimeoutMs);
    client.setSendTimeout(_receiveTimeoutMs);
    return client;
  }

  /// 测试连通性：能 ping 通并确保目录存在。
  Future<void> testConnection(CloudConfig config) async {
    final client = _client(config);
    try {
      await client.ping();
      await client.mkdirAll(config.rootPath);
    } on DioException catch (error) {
      throw CloudFailure(_describe(error));
    } catch (error) {
      throw CloudFailure(_describe(error));
    }
  }

  // ---------------- 上传 ----------------

  /// 手动备份：立即上传一份，不参与滚动清理。
  Future<CloudFileInfo> backupNow({bool includeExpiredDeleted = false}) async {
    final config = await loadConfig();
    if (config == null) {
      throw const CloudFailure('尚未配置云盘账号，请先填写地址与账号');
    }
    final json = await _backup.buildJson(
      includeExpiredDeleted: includeExpiredDeleted,
    );
    final name = BackupService.buildFileName(
      now: AppClock.now(),
      prefix: '$manualPrefix-v${Defaults.backupVersion}',
    );
    await _upload(config, name, json);
    return CloudFileInfo(
      name: name,
      path: '${config.rootPath}/$name',
      size: utf8.encode(json).length,
      modifiedAt: AppClock.now(),
      isAuto: false,
    );
  }

  /// 前台静默自动备份：不满足条件时什么都不做，也绝不抛异常。
  Future<AutoBackupResult> autoBackup({bool force = false}) async {
    try {
      final config = await loadConfig();
      if (config == null) {
        return const AutoBackupResult(AutoBackupStatus.noConfig);
      }

      final lastAt = _lastSuccess;
      if (!force && lastAt != null) {
        final elapsed = AppClock.nowMillis() - lastAt;
        if (elapsed < Limits.autoBackupInterval.inMilliseconds) {
          return const AutoBackupResult(AutoBackupStatus.notDue);
        }
      }

      // 本地无新写入就跳过，避免每天重复上传同一份数据
      if (!force && lastAt != null) {
        final latestWrite = await latestLocalWriteMillis();
        if (latestWrite == null || latestWrite <= lastAt) {
          return const AutoBackupResult(AutoBackupStatus.noChanges);
        }
      }

      final json = await _backup.buildJson();
      final name = BackupService.buildFileName(
        now: AppClock.now(),
        prefix: '$autoPrefix-v${Defaults.backupVersion}',
      );
      await _upload(config, name, json);
      return AutoBackupResult(AutoBackupStatus.uploaded, fileName: name);
    } on CloudFailure catch (error) {
      return AutoBackupResult(AutoBackupStatus.failed, message: error.message);
    } catch (error) {
      return AutoBackupResult(
        AutoBackupStatus.failed,
        message: _describe(error),
      );
    }
  }

  /// 上次成功时间由调用方（AppSettings）持有，这里只读注入值。

  Future<void> _upload(CloudConfig config, String name, String json) async {
    final client = _client(config);
    final path = '${config.rootPath}/$name';
    try {
      await client.mkdirAll(config.rootPath);
      final bytes = Uint8List.fromList(utf8.encode(json));
      await client.write(path, bytes);
    } on DioException catch (error) {
      throw CloudFailure(_describe(error));
    } catch (error) {
      throw CloudFailure(_describe(error));
    }
  }

  // ---------------- 列表 / 下载 ----------------

  Future<List<CloudFileInfo>> listBackups() async {
    final config = await loadConfig();
    if (config == null) {
      throw const CloudFailure('尚未配置云盘账号');
    }
    final client = _client(config);
    try {
      final files = await client.readDir(config.rootPath);
      final result = <CloudFileInfo>[
        for (final file in files)
          if (file.isDir != true && (file.name ?? '').endsWith('.json'))
            CloudFileInfo(
              name: file.name ?? '',
              path: file.path ?? '${config.rootPath}/${file.name}',
              size: file.size ?? 0,
              modifiedAt: file.mTime,
              isAuto: (file.name ?? '').startsWith(autoPrefix),
            ),
      ];
      result.sort((a, b) {
        final left = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
        final right = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
        return right.compareTo(left);
      });
      return result;
    } on DioException catch (error) {
      throw CloudFailure(_describe(error));
    } catch (error) {
      throw CloudFailure(_describe(error));
    }
  }

  /// 下载一份云端备份的文本内容，交给本地恢复流程做校验与预览。
  Future<String> downloadBackup(String name) async {
    final config = await loadConfig();
    if (config == null) {
      throw const CloudFailure('尚未配置云盘账号');
    }
    final client = _client(config);
    try {
      final bytes = await client.read('${config.rootPath}/$name');
      return utf8.decode(bytes, allowMalformed: true);
    } on DioException catch (error) {
      throw CloudFailure(_describe(error));
    } catch (error) {
      throw CloudFailure(_describe(error));
    }
  }

  /// 滚动清理：只保留最近 [keep] 份自动备份，手动备份永不删除。
  /// 返回被删除的文件数。
  Future<int> cleanupAutoBackups({int keep = Limits.cloudAutoBackupKeep}) async {
    final files = await listBackups();
    final autos = files.where((file) => file.isAuto).toList();
    if (autos.length <= keep) return 0;

    final config = await loadConfig();
    if (config == null) return 0;

    final client = _client(config);
    final expired = autos.sublist(keep);
    var removed = 0;
    for (final file in expired) {
      try {
        await client.remove(file.path);
        removed++;
      } catch (_) {
        // 单份删除失败不影响其余清理
      }
    }
    return removed;
  }

  // ---------------- 本地改动检测 ----------------

  /// 最近一次本地写入时间（毫秒）。四张业务表取最大值。
  Future<int?> latestLocalWriteMillis({DatabaseExecutor? ex}) async {
    final executor = ex ?? _db.raw;
    final rows = await executor.rawQuery(
      '''
      SELECT MAX(ts) AS latest FROM (
        SELECT MAX(updated_at) AS ts FROM ${Tables.workers}
        UNION ALL
        SELECT MAX(updated_at) AS ts FROM ${Tables.toys}
        UNION ALL
        SELECT MAX(updated_at) AS ts FROM ${Tables.pieceRecords}
        UNION ALL
        SELECT MAX(updated_at) AS ts FROM ${Tables.adjustments}
        UNION ALL
        SELECT MAX(COALESCE(locked_at, 0)) AS ts FROM ${Tables.lockedMonths}
      )
      ''',
    );
    final value = rows.isEmpty ? null : rows.first['latest'] as int?;
    if (value == null || value <= 0) return null;
    return value;
  }

  // ---------------- 错误文案 ----------------

  String _describe(Object error) {
    if (error is CloudFailure) return error.message;
    if (error is DioException) {
      final status = error.response?.statusCode;
      switch (status) {
        case 401:
          return '账号或应用密码不正确（坚果云需使用「应用密码」而非登录密码）';
        case 403:
          return '没有权限访问该目录，请检查账号权限';
        case 404:
          return '云盘地址不正确，请检查 WebDAV 地址';
        case 405:
          return '云盘拒绝该操作，请确认地址以 / 结尾且支持 WebDAV';
        case 507:
          return '云盘空间不足，请清理后重试';
      }
      if (status != null) return '云盘返回错误（HTTP $status）';
      final type = error.type;
      switch (type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接云盘超时，请检查网络';
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return '无法连接云盘，请检查网络或地址';
        default:
          return '云盘传输失败，请稍后重试';
      }
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return '无法连接云盘，请检查网络或地址';
    }
    if (text.contains('HandshakeException') || text.contains('CERTIFICATE')) {
      return '云盘证书校验失败，请检查地址是否为 https';
    }
    return '操作失败：$text';
  }
}
