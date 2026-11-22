/// 工人档案。同名工人靠 [code]（显示编号）区分，历史记录靠 [id] 关联。
class Worker {
  const Worker({
    required this.id,
    required this.code,
    required this.name,
    required this.pinyinInitials,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.phone = '',
    this.idCard = '',
  });

  factory Worker.fromMap(Map<String, Object?> map) {
    return Worker(
      id: map['id']! as String,
      code: map['code']! as String,
      name: map['name']! as String,
      pinyinInitials: (map['pinyin_initials'] as String?) ?? '',
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
      phone: (map['phone'] as String?) ?? '',
      idCard: (map['id_card'] as String?) ?? '',
    );
  }

  final String id;

  /// 显示编号，固定不变，用于区分同名工人。
  final String code;

  final String name;

  /// 联系电话，选填。老档案为空串。
  final String phone;

  /// 身份证号，选填。老档案为空串。
  ///
  /// 只做档案记录与展示，不参与任何金额计算；
  /// 展示时默认遮罩中间位（见 [maskedIdCard]），需要时再点开看全。
  final String idCard;

  /// 拼音首字母，大写；可手动修正（多音姓氏兜底）。
  final String pinyinInitials;

  /// true = 已停用归档：录入页隐藏，历史与报表仍可查。
  final bool isArchived;

  final int createdAt;
  final int updatedAt;

  /// 列表展示用：「张三（W001）」。
  String get displayName => code.isEmpty ? name : '$name（$code）';

  /// 是否填了至少一项联系方式。
  bool get hasContact => phone.isNotEmpty || idCard.isNotEmpty;

  /// 遮罩后的身份证号：保留前 6 位与后 4 位，中间打星。
  ///
  /// 档案页默认显示这个版本；位数不足时原样返回，避免把异常数据遮成一片星号。
  String get maskedIdCard {
    if (idCard.length < 10) return idCard;
    final head = idCard.substring(0, 6);
    final tail = idCard.substring(idCard.length - 4);
    return '$head********$tail';
  }

  Worker copyWith({
    String? code,
    String? name,
    String? phone,
    String? idCard,
    String? pinyinInitials,
    bool? isArchived,
    int? updatedAt,
  }) {
    return Worker(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      idCard: idCard ?? this.idCard,
      pinyinInitials: pinyinInitials ?? this.pinyinInitials,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'phone': phone,
        'id_card': idCard,
        'pinyin_initials': pinyinInitials,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
