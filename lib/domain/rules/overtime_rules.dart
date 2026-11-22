import '../../core/constants.dart';
import '../../core/money.dart';
import '../../data/models/toy.dart';

/// 一次加班计价的结果：实际单价 + 用于展示的倍率。
class OvertimePricing {
  const OvertimePricing({
    required this.priceTenThousandth,
    required this.multiplierPerMille,
  });

  /// 实际参与计算的单价（万分之一元）。
  final int priceTenThousandth;

  /// 与正常单价的比值，千分比（1500 = 1.5 倍）。仅用于展示与审计。
  final int multiplierPerMille;

  String get priceLabel => Money.formatPrice(priceTenThousandth);

  String get multiplierLabel => Money.formatMultiplier(multiplierPerMille);
}

/// 加班规则的**唯一实现**。
///
/// 界面负责展示，仓储负责落库，两边都调这里，避免各算一套算出两个价。
class OvertimeRules {
  OvertimeRules._();

  /// 按设置里的口径算加班单价。
  ///
  /// 优先级：
  /// 1. 口径 = 按加班单价，且玩具填了加班价 → 用它；
  /// 2. 其余情况（含「按加班单价但玩具没填」）→ 正常单价 × 倍率。
  ///
  /// 第 2 条是**故意的兜底**：否则新玩具忘填加班价时，加班就成了白干，
  /// 一个月下来是实打实的少发工资。
  static OvertimePricing resolve({
    required Toy toy,
    required int basePriceTenThousandth,
    required OvertimeMode mode,
    required int multiplierPerMille,
  }) {
    final base = basePriceTenThousandth < 0 ? 0 : basePriceTenThousandth;
    final multiplier = _clampMultiplier(multiplierPerMille);

    if (mode == OvertimeMode.unitPrice && toy.hasOvertimePrice) {
      final price = toy.overtimePriceTenThousandth;
      return OvertimePricing(
        priceTenThousandth: price,
        // 反推倍率，base 为 0（免费工序）时按 1.0 展示，避免除零。
        multiplierPerMille:
            base <= 0 ? 1000 : (price * 1000 + base ~/ 2) ~/ base,
      );
    }

    return OvertimePricing(
      priceTenThousandth: Money.applyMultiplier(base, multiplier),
      multiplierPerMille: multiplier,
    );
  }

  /// 倍率夹取到 [1000, 3000]，防止手滑输入 15 倍把工资算飞。
  static int _clampMultiplier(int multiplierPerMille) {
    if (multiplierPerMille < Limits.minOvertimeMultiplierPerMille) {
      return Limits.minOvertimeMultiplierPerMille;
    }
    if (multiplierPerMille > Limits.maxOvertimeMultiplierPerMille) {
      return Limits.maxOvertimeMultiplierPerMille;
    }
    return multiplierPerMille;
  }

  /// 按时间自动判定：晚于「正常下班时间」就算加班。
  ///
  /// 只是界面上的**预勾选**，用户仍可手动改回；
  /// 因为常有人晚上补录白天干的活，自动判定只做初始值，不做强制。
  static bool shouldPrecheckOvertime({
    required int minuteOfDay,
    required int workEndMinute,
    required bool autoDetect,
  }) {
    if (!autoDetect) return false;
    return minuteOfDay >= workEndMinute;
  }
}
