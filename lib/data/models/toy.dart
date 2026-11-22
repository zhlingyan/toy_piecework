import '../../core/constants.dart';
import '../../core/money.dart';

/// 玩具 + 工序档案。单价以万分之一元整数存储。
class Toy {
  const Toy({
    required this.id,
    required this.name,
    required this.process,
    required this.unitPriceTenThousandth,
    this.overtimePriceTenThousandth = 0,
    required this.pinyinInitials,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Toy.fromMap(Map<String, Object?> map) {
    return Toy(
      id: map['id']! as String,
      name: map['name']! as String,
      process: (map['process'] as String?) ?? Defaults.defaultProcess,
      unitPriceTenThousandth: map['unit_price_ten_thousandth']! as int,
      overtimePriceTenThousandth:
          (map['overtime_price_ten_thousandth'] as int?) ?? 0,
      pinyinInitials: (map['pinyin_initials'] as String?) ?? '',
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
    );
  }

  final String id;
  final String name;

  /// 工序名，默认「整件」。
  final String process;

  /// 当前单价，单位万分之一元（0.035 元 => 350）。
  final int unitPriceTenThousandth;

  /// 加班单价，单位万分之一元。
  ///
  /// 0 表示**未单独设置**：此时即使设置里选了「按加班单价」，
  /// 也会自动回退到「正常单价 × 倍率」，不会出现加班等于白干。
  final int overtimePriceTenThousandth;

  final String pinyinInitials;
  final bool isArchived;
  final int createdAt;
  final int updatedAt;

  String get displayName =>
      process == Defaults.defaultProcess ? name : '$name / $process';

  /// 单价文本，**不带单位**。
  ///
  /// 单位由界面按语境单独给出（如「单价 0.20」/「小计 12.00 元」）。
  /// 早先这里自带「 元」，既会和调用处拼成「0.20 元 元」，
  /// 又会被直接灌进数字输入框导致解析失败（「本次单价」那个坑），
  /// 所以统一成纯数字，由展示层决定要不要加单位。
  String get priceLabel => Money.formatPrice(unitPriceTenThousandth);

  bool get hasOvertimePrice => overtimePriceTenThousandth > 0;

  String get overtimePriceLabel =>
      Money.formatPrice(overtimePriceTenThousandth);

  Toy copyWith({
    String? name,
    String? process,
    int? unitPriceTenThousandth,
    int? overtimePriceTenThousandth,
    String? pinyinInitials,
    bool? isArchived,
    int? updatedAt,
  }) {
    return Toy(
      id: id,
      name: name ?? this.name,
      process: process ?? this.process,
      unitPriceTenThousandth:
          unitPriceTenThousandth ?? this.unitPriceTenThousandth,
      overtimePriceTenThousandth:
          overtimePriceTenThousandth ?? this.overtimePriceTenThousandth,
      pinyinInitials: pinyinInitials ?? this.pinyinInitials,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'process': process,
        'unit_price_ten_thousandth': unitPriceTenThousandth,
        'overtime_price_ten_thousandth': overtimePriceTenThousandth,
        'pinyin_initials': pinyinInitials,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
