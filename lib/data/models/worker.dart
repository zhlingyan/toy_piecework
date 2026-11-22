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
    );
  }

  final String id;

  /// 显示编号，固定不变，用于区分同名工人。
  final String code;

  final String name;

  /// 拼音首字母，大写；可手动修正（多音姓氏兜底）。
  final String pinyinInitials;

  /// true = 已停用归档：录入页隐藏，历史与报表仍可查。
  final bool isArchived;

  final int createdAt;
  final int updatedAt;

  /// 列表展示用：「张三（W001）」。
  String get displayName => code.isEmpty ? name : '$name（$code）';

  Worker copyWith({
    String? code,
    String? name,
    String? pinyinInitials,
    bool? isArchived,
    int? updatedAt,
  }) {
    return Worker(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
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
        'pinyin_initials': pinyinInitials,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
