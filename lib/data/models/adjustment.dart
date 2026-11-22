import '../../core/constants.dart';
import '../../core/money.dart';

/// 奖惩 / 计时 / 预支调整项。金额统一存正数，方向由 [AdjustmentType.sign] 决定。
class Adjustment {
  const Adjustment({
    required this.id,
    required this.date,
    required this.workerId,
    required this.workerNameSnapshot,
    required this.type,
    required this.amountCents,
    required this.remark,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Adjustment.fromMap(Map<String, Object?> map) {
    return Adjustment(
      id: map['id']! as String,
      date: map['date']! as String,
      workerId: map['worker_id']! as String,
      workerNameSnapshot: map['worker_name_snapshot']! as String,
      type: AdjustmentType.fromCode(map['type']! as String),
      amountCents: map['amount_cents']! as int,
      remark: (map['remark'] as String?) ?? '',
      deletedAt: map['deleted_at'] as int?,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
    );
  }

  final String id;
  final String date;
  final String workerId;
  final String workerNameSnapshot;
  final AdjustmentType type;

  /// 金额（分），恒为正数。
  final int amountCents;

  /// 必填，用于月底核对。
  final String remark;

  final int? deletedAt;
  final int createdAt;
  final int updatedAt;

  bool get isDeleted => deletedAt != null;

  /// 计入应付的带符号金额（分）。
  int get signedCents => type.sign * amountCents;

  String get amountLabel => Money.formatCents(amountCents);

  Adjustment copyWith({
    String? date,
    String? workerId,
    String? workerNameSnapshot,
    AdjustmentType? type,
    int? amountCents,
    String? remark,
    int? deletedAt,
    bool clearDeletedAt = false,
    int? updatedAt,
  }) {
    return Adjustment(
      id: id,
      date: date ?? this.date,
      workerId: workerId ?? this.workerId,
      workerNameSnapshot: workerNameSnapshot ?? this.workerNameSnapshot,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
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
        'worker_name_snapshot': workerNameSnapshot,
        'type': type.code,
        'amount_cents': amountCents,
        'remark': remark,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
