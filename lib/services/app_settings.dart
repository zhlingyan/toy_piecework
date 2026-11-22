import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// 轻量本地设置（连录开关、云备份时间等）。
///
/// 不落业务表，避免污染账本结构；换机时这些偏好可重建。
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  static const String _kKeepWorker = 'keep_worker';
  static const String _kKeepToy = 'keep_toy';
  static const String _kLastCloudBackupAt = 'last_cloud_backup_at';
  static const String _kLastCloudBackupError = 'last_cloud_backup_error';
  static const String _kCloudAutoEnabled = 'cloud_auto_enabled';
  static const String _kOvertimeMode = 'overtime_mode';
  static const String _kOvertimeMultiplier = 'overtime_multiplier';
  static const String _kOvertimeAutoDetect = 'overtime_auto_detect';
  static const String _kWorkEndMinute = 'work_end_minute';
  static const String _kFontScale = 'font_scale';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }

  /// 连录：保存后是否保留已选工人。
  bool get keepWorker => _prefs.getBool(_kKeepWorker) ?? true;

  /// 连录：保存后是否保留已选工序。
  bool get keepToy => _prefs.getBool(_kKeepToy) ?? true;

  Future<void> setKeepWorker(bool value) async {
    await _prefs.setBool(_kKeepWorker, value);
    notifyListeners();
  }

  Future<void> setKeepToy(bool value) async {
    await _prefs.setBool(_kKeepToy, value);
    notifyListeners();
  }

  int? get lastCloudBackupAt => _prefs.getInt(_kLastCloudBackupAt);

  String? get lastCloudBackupError => _prefs.getString(_kLastCloudBackupError);

  bool get cloudAutoEnabled => _prefs.getBool(_kCloudAutoEnabled) ?? false;

  Future<void> setCloudAutoEnabled(bool value) async {
    await _prefs.setBool(_kCloudAutoEnabled, value);
    notifyListeners();
  }

  Future<void> markCloudBackupSuccess() async {
    await _prefs.setInt(_kLastCloudBackupAt, DateTime.now().millisecondsSinceEpoch);
    await _prefs.remove(_kLastCloudBackupError);
    notifyListeners();
  }

  Future<void> markCloudBackupFailure(String message) async {
    await _prefs.setString(_kLastCloudBackupError, message);
    notifyListeners();
  }

  // ---- 加班口径 ----

  /// 按倍数还是按玩具加班单价。
  OvertimeMode get overtimeMode =>
      OvertimeMode.fromCode(_prefs.getString(_kOvertimeMode));

  Future<void> setOvertimeMode(OvertimeMode mode) async {
    await _prefs.setString(_kOvertimeMode, mode.code);
    notifyListeners();
  }

  /// 加班倍率，千分比（1500 = 1.5 倍）。
  int get overtimeMultiplierPerMille =>
      _prefs.getInt(_kOvertimeMultiplier) ?? Defaults.overtimeMultiplierPerMille;

  Future<void> setOvertimeMultiplierPerMille(int perMille) async {
    final clamped = perMille.clamp(
      Limits.minOvertimeMultiplierPerMille,
      Limits.maxOvertimeMultiplierPerMille,
    );
    await _prefs.setInt(_kOvertimeMultiplier, clamped);
    notifyListeners();
  }

  /// 是否按「晚于下班时间」自动预勾加班。
  bool get overtimeAutoDetect => _prefs.getBool(_kOvertimeAutoDetect) ?? true;

  Future<void> setOvertimeAutoDetect(bool value) async {
    await _prefs.setBool(_kOvertimeAutoDetect, value);
    notifyListeners();
  }

  /// 正常下班时间（当天第几分钟），默认 18:00。
  int get workEndMinute => _prefs.getInt(_kWorkEndMinute) ?? Defaults.workEndMinute;

  Future<void> setWorkEndMinute(int minuteOfDay) async {
    final clamped = minuteOfDay.clamp(0, 24 * 60 - 1);
    await _prefs.setInt(_kWorkEndMinute, clamped);
    notifyListeners();
  }

  // ---- 字号 ----

  /// 字号倍数：1.0 标准 / 1.3 大 / 1.6 超大。
  double get fontScale => _prefs.getDouble(_kFontScale) ?? Defaults.fontScaleStandard;

  Future<void> setFontScale(double scale) async {
    await _prefs.setDouble(_kFontScale, scale);
    notifyListeners();
  }
}
