/// 业务异常：全部带可直接展示给车间管理员的中文提示。
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 表单/业务校验失败。
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

/// 目标月份已锁账，拒绝写入。
class LockedMonthFailure extends AppFailure {
  LockedMonthFailure(this.months)
      : super(
          '${months.map(_prettyMonth).join('、')} 已锁账，需先在「结算页」解锁后才能修改',
        );

  final List<String> months;

  static String _prettyMonth(String ym) {
    final parts = ym.split('-');
    if (parts.length != 2) return ym;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }
}

/// 删除超过 30 天，回收站不再提供恢复。
class TrashExpiredFailure extends AppFailure {
  const TrashExpiredFailure()
      : super('该记录删除已超过 30 天，按规则不可恢复');
}

/// 备份/恢复文件不合法。
class BackupFailure extends AppFailure {
  const BackupFailure(super.message);
}

/// 旧账导入文件不合法。
class LegacyImportFailure extends AppFailure {
  const LegacyImportFailure(super.message);
}

/// 云端同步失败（不阻塞本地记账，仅提示）。
class CloudFailure extends AppFailure {
  const CloudFailure(super.message);
}

/// 本地文件/相册读写失败（分享、存图等）。
class FileFailure extends AppFailure {
  const FileFailure(super.message);
}
