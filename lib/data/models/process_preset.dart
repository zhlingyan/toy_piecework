/// 工序预选项。
///
/// 分两类：
/// * **预置项**（`is_builtin = 1`）：建库时写入，不允许删除，顺序固定；
/// * **自定义项**：用户在「新增工序」里加的名字，落库后一直留在列表里。
class ProcessPreset {
  const ProcessPreset({
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
  });

  factory ProcessPreset.fromMap(Map<String, Object?> map) {
    return ProcessPreset(
      name: map['name']! as String,
      isBuiltin: ((map['is_builtin'] as int?) ?? 0) != 0,
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  /// 工序名，同时是主键（天然去重）。
  final String name;

  /// 是否为预置项（预置项不可删除）。
  final bool isBuiltin;

  /// 预置项内部顺序；自定义项统一为 0，靠创建时间排。
  final int sortOrder;

  /// 列表右侧的标记文案。
  String get badge => isBuiltin ? '常用' : '自定义';
}
