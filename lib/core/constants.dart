/// 全局常量：表名、枚举、阈值、云端预设。
library;

class Tables {
  Tables._();

  static const String workers = 'workers';
  static const String toys = 'toys';
  static const String pieceRecords = 'piece_records';
  static const String adjustments = 'adjustments';
  static const String lockedMonths = 'locked_months';
}

/// 调整项类型：统一录正数，按 [sign] 决定加减。
enum AdjustmentType {
  bonus('bonus', '补贴', 1),
  hourly('hourly', '计时', 1),
  deduction('deduction', '扣款', -1),
  advance('advance', '预支', -1);

  const AdjustmentType(this.code, this.label, this.sign);

  /// 落库值。
  final String code;

  /// 界面文案。
  final String label;

  /// +1 计入应付，-1 从应付扣减。
  final int sign;

  static AdjustmentType fromCode(String code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    throw ArgumentError('未知调整类型: $code');
  }

  static AdjustmentType? tryFromCode(String code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

class Limits {
  Limits._();

  /// 单笔件数超过此值需二次确认。
  static const int confirmQuantityAbove = 5000;

  /// 单笔金额（分）超过此值需二次确认，即 2000.00 元。
  static const int confirmSubtotalCentsAbove = 200000;

  /// 回收站可恢复窗口天数。
  static const int trashRetentionDays = 30;

  /// 云端自动备份保留份数。
  static const int cloudAutoBackupKeep = 30;

  /// 自动备份最小间隔。
  static const Duration autoBackupInterval = Duration(hours: 24);
}

class Defaults {
  Defaults._();

  /// 玩具工序默认值。
  static const String defaultProcess = '整件';

  /// 坚果云 WebDAV 地址。
  static const String jianguoyunUrl = 'https://dav.jianguoyun.com/dav/';

  /// 云端备份目录（位于 WebDAV 根下）。
  ///
  /// 刻意用 ASCII 名：部分 WebDAV 服务对中文路径的百分号编码处理不一致，
  /// 用纯英文目录名可以完全绕开这一类兼容问题；用户可在设置页自行改名。
  static const String cloudBackupDir = 'toy_piecework';

  /// 备份文件格式标识与版本。
  static const String backupFormat = 'toy_piecework_backup';
  static const int backupVersion = 1;
}
