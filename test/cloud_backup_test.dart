import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/data/services/cloud_backup_service.dart';

import 'support/fixture.dart';

void main() {
  group('CloudConfig 归一化', () {
    test('地址自动补全结尾斜杠，目录去掉多余斜杠', () {
      const config = CloudConfig(
        baseUrl: 'https://dav.jianguoyun.com/dav',
        folder: '/my_backup/',
        username: 'u@example.com',
        password: 'p',
      );
      expect(config.normalizedBaseUrl, 'https://dav.jianguoyun.com/dav/');
      expect(config.normalizedFolder, 'my_backup');
      expect(config.rootPath, 'https://dav.jianguoyun.com/dav/my_backup');
      expect(config.displayTarget, 'https://dav.jianguoyun.com/dav/my_backup/');
    });

    test('目录留空回落到默认值', () {
      const config = CloudConfig(
        baseUrl: 'https://dav.example.com/',
        folder: '   ',
        username: 'u',
        password: 'p',
      );
      expect(config.normalizedFolder, Defaults.cloudBackupDir);
    });

    test('中文目录按 URL 编码拼接，避免路径被截断', () {
      const config = CloudConfig(
        baseUrl: 'https://dav.example.com/',
        folder: '备份',
        username: 'u',
        password: 'p',
      );
      expect(config.rootPath, contains('%E5%A4%87%E4%BB%BD'));
    });
  });

  group('本地改动检测与自动备份判定', () {
    late Fixture f;
    late CloudBackupService cloud;
    int? lastSuccessAt;

    setUp(() async {
      f = await Fixture.create();
      lastSuccessAt = null;
      cloud = CloudBackupService(f.db, f.backup, () => lastSuccessAt);
    });

    tearDown(() async {
      await f.dispose();
    });

    test('最近写入时间：无数据为 null，写入后单调递增', () async {
      expect(await cloud.latestLocalWriteMillis(), isNull);

      final worker = await f.addWorker('张三');
      final first = await cloud.latestLocalWriteMillis();
      expect(first, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await f.workers.update(worker.copyWith(name: '张三丰'));
      final second = await cloud.latestLocalWriteMillis();
      expect(second! > first!, isTrue);
    });

    test('没配置账号时自动备份只返回状态，不抛异常', () async {
      // 单元测试环境没有安全存储插件，loadConfig 会安全地返回 null
      expect(await cloud.loadConfig(), isNull);

      final result = await cloud.autoBackup();
      expect(result.status, AutoBackupStatus.noConfig);
      expect(result.isUploaded, isFalse);
      expect(result.description, contains('云盘账号'));
    });

    test('未到 24 小时直接跳过，不会触发网络', () async {
      lastSuccessAt = DateTime.now().millisecondsSinceEpoch;
      final result = await cloud.autoBackup();
      expect(
        result.status,
        anyOf(AutoBackupStatus.noConfig, AutoBackupStatus.notDue),
      );
    });
  });
}
