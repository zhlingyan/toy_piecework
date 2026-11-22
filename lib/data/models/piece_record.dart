import '../../core/money.dart';

/// 计件流水。姓名/玩具/工序/单价全部**强制快照**，
/// 档案改名、调价、归档都不会篡改历史账目。
class PieceRecord {
  const PieceRecord({
    required this.id,
    required this.date,
    required this.workerId,
    required this.toyId,
    required this.workerNameSnapshot,
    required this.toyNameSnapshot,
    required this.processSnapshot,
    required this.unitPriceSnapshot,
    required this.quantity,
    required this.subtotalCents,
    required this.remark,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PieceRecord.fromMap(Map<String, Object?> map) {
    return PieceRecord(
      id: map['id']! as String,
      date: map['date']! as String,
      workerId: map['worker_id']! as String,
      toyId: map['toy_id']! as String,
      workerNameSnapshot: map['worker_name_snapshot']! as String,
      toyNameSnapshot: map['toy_name_snapshot']! as String,
      processSnapshot: map['process_snapshot']! as String,
      unitPriceSnapshot: map['unit_price_snapshot']! as int,
      quantity: map['quantity']! as int,
      subtotalCents: map['subtotal_cents']! as int,
      remark: (map['remark'] as String?) ?? '',
      deletedAt: map['deleted_at'] as int?,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
    );
  }

  final String id;

  /// `YYYY-MM-DD`。
  final String date;

  final String workerId;
  final String toyId;
  final String workerNameSnapshot;
  final String toyNameSnapshot;

  /// 工序快照，参与结算分组。
  final String processSnapshot;

  /// 单价快照，单位万分之一元。
  final int unitPriceSnapshot;

  final int quantity;

  /// 小计（分），逐笔取整后入库。
  final int subtotalCents;

  final String remark;

  /// NULL = 正常；非 NULL = 已删除（软删除，永不物理删除）。
  final int? deletedAt;

  final int createdAt;
  final int updatedAt;

  bool get isDeleted => deletedAt != null;

  String get priceLabel => Money.formatPrice(unitPriceSnapshot);

  String get subtotalLabel => Money.formatCents(subtotalCents);

  PieceRecord copyWith({
    String? date,
    String? workerId,
    String? toyId,
    String? workerNameSnapshot,
    String? toyNameSnapshot,
    String? processSnapshot,
    int? unitPriceSnapshot,
    int? quantity,
    int? subtotalCents,
    String? remark,
    int? deletedAt,
    bool clearDeletedAt = false,
    int? updatedAt,
  }) {
    return PieceRecord(
      id: id,
      date: date ?? this.date,
      workerId: workerId ?? this.workerId,
      toyId: toyId ?? this.toyId,
      workerNameSnapshot: workerNameSnapshot ?? this.workerNameSnapshot,
      toyNameSnapshot: toyNameSnapshot ?? this.toyNameSnapshot,
      processSnapshot: processSnapshot ?? this.processSnapshot,
      unitPriceSnapshot: unitPriceSnapshot ?? this.unitPriceSnapshot,
      quantity: quantity ?? this.quantity,
      subtotalCents: subtotalCents ?? this.subtotalCents,
      remark: remark ?? this.remark,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'worker_id': workerId,
        'toy_id': toyId,
        'worker_name_snapshot': workerNameSnapshot,
        'toy_name_snapshot': toyNameSnapshot,
        'process_snapshot': processSnapshot,
        'unit_price_snapshot': unitPriceSnapshot,
        'quantity': quantity,
        'subtotal_cents': subtotalCents,
        'remark': remark,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
