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

/// 加班计费口径（设置页可切换）。
///
/// 同一个厂里不同车间习惯不一样：有的按倍率乘，有的给每个玩具单独定加班价。
/// 两种都要支持，落库时一律把**实际计价单价**快照进流水，
/// 以后改设置不会倒算历史账。
enum OvertimeMode {
  /// 加班单价 = 正常单价 × 倍率。
  multiplier('multiplier', '按倍数'),

  /// 加班单价取玩具档案里单独填的「加班单价」。
  unitPrice('unitPrice', '按加班单价');

  const OvertimeMode(this.code, this.label);

  /// 落库值。
  final String code;

  /// 界面文案。
  final String label;

  static OvertimeMode fromCode(String? code) {
    for (final mode in values) {
      if (mode.code == code) return mode;
    }
    return OvertimeMode.multiplier;
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

  /// 加班倍率上限（千分比），3000 = 3.0 倍。防止手滑输入 15 倍。
  static const int maxOvertimeMultiplierPerMille = 3000;

  /// 加班倍率下限（千分比），1000 = 1.0 倍（等于不加成）。
  static const int minOvertimeMultiplierPerMille = 1000;
}

class Defaults {
  Defaults._();

  /// 玩具工序默认值。
  static const String defaultProcess = '整件';

  /// 默认加班倍率，千分比：1500 = 1.5 倍。
  static const int overtimeMultiplierPerMille = 1500;

  /// 默认正常下班时间（当天第几分钟），18:00 = 1080。
  ///
  /// 晚于此刻录入的流水在界面上自动预勾「加班」，仍可手动改回。
  static const int workEndMinute = 18 * 60;

  /// 默认字号档位倍数。
  static const double fontScaleStandard = 1.0;
  static const double fontScaleLarge = 1.3;
  static const double fontScaleHuge = 1.6;

  /// 坚果云 WebDAV 地址。
  static const String jianguoyunUrl = 'https://dav.jianguoyun.com/dav/';

  /// 云端备份目录（位于 WebDAV 根下）。
  ///
  /// 刻意用 ASCII 名：部分 WebDAV 服务对中文路径的百分号编码处理不一致，
  /// 用纯英文目录名可以完全绕开这一类兼容问题；用户可在设置页自行改名。
  static const String cloudBackupDir = 'toy_piecework';

  /// 备份文件格式标识与版本。
  static const String backupFormat = 'toy_piecework_backup';
  static const int backupVersion = 2;
}
