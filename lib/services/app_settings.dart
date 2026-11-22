import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
