/// 柔性校验：只给提醒，不阻断保存。
///
/// 电话和身份证号都是**选填**，而且厂里真实数据什么样都有：
/// 座机带区号、号码中间加空格、身份证最后一位是 X、老档案甚至是手抄错位。
/// 因此这里一律返回「提示文案」而不是抛异常——用户可以照着提示改，
/// 也可以确认无误后直接保存，绝不因为格式把账卡死。
class Validators {
  Validators._();

  /// 电话号码提醒；`null` 表示看起来正常（或没填）。
  static String? phoneWarning(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.length > 24) return '电话号码太长了，确认没粘多再保存';
    if (RegExp(r'[^0-9+\-() ]').hasMatch(value)) {
      return '电话号码里有不常见字符，确认无误可以照常保存';
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return '电话号码位数偏少，确认无误可以照常保存';
    if (digits.length > 15) return '电话号码位数偏多，确认无误可以照常保存';
    return null;
  }

  /// 身份证号提醒；`null` 表示看起来正常（或没填）。
  ///
  /// 18 位校验位算错的场景多半是抄错一位，提醒一句比直接拒绝有用得多。
  static String? idCardWarning(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.isEmpty) return null;
    if (value.length != 18) return '身份证号一般是 18 位，确认无误可以照常保存';
    if (!RegExp(r'^\d{17}[\dX]$').hasMatch(value)) {
      return '身份证号格式看起来不对（前 17 位数字，最后一位数字或 X）';
    }
    if (!idCardChecksumOk(value)) {
      return '身份证号校验位对不上，请再核对一遍（不影响保存）';
    }
    return null;
  }

  /// 18 位身份证的校验位算法（GB 11643-1999）。
  static bool idCardChecksumOk(String value) {
    if (!RegExp(r'^\d{17}[\dX]$').hasMatch(value)) return false;
    const weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
    const codes = '10X98765432';
    var sum = 0;
    for (var i = 0; i < 17; i++) {
      sum += int.parse(value[i]) * weights[i];
    }
    return codes[sum % 11] == value[17];
  }
}
