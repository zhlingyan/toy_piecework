/// 金额工具：全链路只使用整数，杜绝浮点误差。
///
/// 单位约定：
/// * 单价（`unit_price_ten_thousandth`）：万分之一元，例 0.035 元 => 350
/// * 小计 / 调整项 / 工资（`*_cents`）：分，例 45.00 元 => 4500
class Money {
  Money._();

  static const int tenThousandthPerYuan = 10000;
  static const int centsPerYuan = 100;

  /// 单笔小计（分）= round(数量 × 单价 / 100)，四舍五入到分。
  ///
  /// 数量与单价均为正整数，`(x + 50) ~/ 100` 等价于对 x/100 做 half-up 取整。
  /// 例：100 件 × 350（0.035 元）= 35000 => 350 分 = 3.50 元。
  static int subtotalCents({
    required int quantity,
    required int priceTenThousandth,
  }) {
    assert(quantity > 0, '数量必须为正整数');
    assert(priceTenThousandth >= 0, '单价不能为负');
    return (quantity * priceTenThousandth + 50) ~/ 100;
  }

  /// 加班倍率换算：单价 × 倍率，四舍五入到万分之一元。
  ///
  /// 倍率用**千分比**表示（1500 = 1.5 倍），这样 1.25、1.8 这类非整数倍
  /// 也能精确落在整数上，不必引入 double。
  /// 例：0.20 元（2000）× 1.5 => 3000（0.30 元）。
  static int applyMultiplier(int priceTenThousandth, int multiplierPerMille) {
    assert(priceTenThousandth >= 0, '单价不能为负');
    assert(multiplierPerMille > 0, '倍率必须大于 0');
    if (multiplierPerMille == 1000) return priceTenThousandth;
    return (priceTenThousandth * multiplierPerMille + 500) ~/ 1000;
  }

  /// 倍率展示：1500 => "1.5"，1250 => "1.25"，1000 => "1.0"。
  static String formatMultiplier(int multiplierPerMille) {
    final whole = multiplierPerMille ~/ 1000;
    var frac = (multiplierPerMille % 1000).toString().padLeft(3, '0');
    while (frac.length > 1 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return '$whole.$frac';
  }

  /// 把「元」字符串解析为万分之一元整数，最多支持 4 位小数。
  /// 超过 4 位时按第 5 位四舍五入（用户输入 0.03599 得 0.0360，不抛错）。
  /// 非法输入返回 null，由调用方决定提示文案。
  static int? tryParsePrice(String raw) => _parseScaled(raw, 4);

  /// 把「元」字符串解析为分，用于调整项金额录入（最多 2 位小数）。
  static int? tryParseCents(String raw) => _parseScaled(raw, 2);

  /// 计时工资（分）= round(工时分钟 × 时薪分/时 ÷ 60)。
  ///
  /// 全整数运算，只在最后一步四舍五入一次：
  /// 例 210 分钟（3.5 小时）× 2500 分/时 = 8750 分 = 87.50 元。
  static int hourlyCents({required int minutes, required int rateCentsPerHour}) {
    if (minutes <= 0 || rateCentsPerHour <= 0) return 0;
    return (minutes * rateCentsPerHour + 30) ~/ 60;
  }

  /// 把「小时」字符串解析成分钟，最多 2 位小数（0.25 小时 = 15 分钟）。
  ///
  /// 非法或负数返回 null，由调用方给提示。
  static int? tryParseHoursToMinutes(String raw) {
    final hundredths = _parseScaled(raw.trim(), 2);
    if (hundredths == null || hundredths < 0) return null;
    // 百分之一小时 → 分钟，half-up 取整
    return (hundredths * 60 + 50) ~/ 100;
  }

  /// 工时展示：210 => "3.5"，15 => "0.25"，120 => "2"。
  static String formatHours(int minutes) {
    if (minutes <= 0) return '0';
    final whole = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$whole';
    var frac = ((rest * 100 + 30) ~/ 60).toString().padLeft(2, '0');
    while (frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return '$whole.$frac';
  }

  static int? _parseScaled(String raw, int scale) {
    var s = normalizeDigits(raw).trim();
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    s = s.replaceAll(',', '').replaceAll('，', '');
    if (s.isEmpty) return null;

    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(s);
    if (match == null) return null;
    final intPart = match.group(1) ?? '';
    final fracPart = match.group(2) ?? '';
    if (intPart.isEmpty && fracPart.isEmpty) return null;

    final all = BigInt.parse('$intPart$fracPart'.isEmpty ? '0' : '$intPart$fracPart');
    final shift = scale - fracPart.length;
    BigInt scaled;
    if (shift >= 0) {
      scaled = all * BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      // 正数 half-up：加上半个除数再整除
      scaled = (all + divisor ~/ BigInt.two) ~/ divisor;
    }
    final result = scaled.toInt();
    return negative ? -result : result;
  }

  /// 全角数字 / 符号归一化，兼容长辈输入法与中文标点。
  static String normalizeDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFF10 + 0x30); // ０-９ => 0-9
      } else if (rune == 0xFF0E || rune == 0x3002) {
        buffer.write('.');
      } else if (rune == 0xFF0B) {
        buffer.write('+');
      } else if (rune == 0xFF0D) {
        buffer.write('-');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// 单价展示：至少 2 位小数，最多 4 位，末尾多余的 0 去掉。
  /// 350 => "0.035"，2000 => "0.20"，12345 => "1.2345"。
  static String formatPrice(int priceTenThousandth) {
    final negative = priceTenThousandth < 0;
    final abs = priceTenThousandth.abs();
    final yuan = abs ~/ tenThousandthPerYuan;
    var frac = (abs % tenThousandthPerYuan).toString().padLeft(4, '0');
    while (frac.length > 2 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return '${negative ? '-' : ''}$yuan.$frac';
  }

  /// 金额展示：固定两位小数。4500 => "45.00"。
  static String formatCents(int cents) {
    final negative = cents < 0;
    final abs = cents.abs();
    final yuan = abs ~/ centsPerYuan;
    final frac = (abs % centsPerYuan).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$yuan.$frac';
  }

  /// 带符号金额，用于调整项明细（+20.00 / -5.00）。
  static String formatCentsSigned(int cents) {
    if (cents > 0) return '+${formatCents(cents)}';
    return formatCents(cents);
  }
}
