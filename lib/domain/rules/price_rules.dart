/// 单价口径：**档案价**（永久）与**临时价**（单笔）严格分开。
///
/// 全项目只有一条规则：
/// * 档案里的 `unit_price_ten_thousandth` 是「以后新录入默认用的价」，
///   只有「设置 → 玩具工序」能改；
/// * 每条流水上的 `unit_price_snapshot` 是「这一笔实际用的价」，
///   计数页改价只写这里，**永不回写档案**；
/// * 两者不一致时，这一笔就是「临时调价」，列表里打标签，
///   免得事后有人以为档案被改过、或者把这笔当成标准价去对账。
library;

class PriceRules {
  PriceRules._();

  /// 这一笔是否使用了与档案不同的临时单价。
  ///
  /// [baseUnitPrice] 为 0 表示档案单价未设置或档案已不存在，
  /// 此时**不判定为临时调价**——没有基准就没有「偏离基准」，
  /// 宁可少标一个标签，也不要凭空给历史账扣一顶帽子。
  static bool isTemporary({
    required int recordUnitPrice,
    required int baseUnitPrice,
  }) {
    if (baseUnitPrice <= 0) return false;
    return recordUnitPrice != baseUnitPrice;
  }

  /// 临时调价的说明文案：`档案 0.20 → 本次 0.25`。
  static String temporaryHint({
    required int recordUnitPrice,
    required int baseUnitPrice,
    required String Function(int) formatPrice,
  }) {
    return '档案 ${formatPrice(baseUnitPrice)} → 本次 ${formatPrice(recordUnitPrice)}';
  }
}
