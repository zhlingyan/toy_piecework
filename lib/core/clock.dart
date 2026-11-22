/// 可注入的时钟，便于回收站 30 天窗口、锁账时间戳做确定性测试。
class AppClock {
  AppClock._();

  static DateTime Function() _now = DateTime.now;

  static DateTime now() => _now();

  static int nowMillis() => now().millisecondsSinceEpoch;

  /// 仅供测试使用。
  static void override(DateTime Function() fn) => _now = fn;

  /// 仅供测试使用，恢复真实时间。
  static void reset() => _now = DateTime.now;
}
