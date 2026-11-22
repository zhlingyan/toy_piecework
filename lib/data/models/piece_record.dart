import '../../core/dates.dart';
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
    this.minuteOfDay = 0,
    this.overtime = false,
    this.overtimePriceSnapshot = 0,
    this.overtimeMultiplier = 1000,
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
      minuteOfDay: (map['minute_of_day'] as int?) ?? 0,
      overtime: ((map['overtime'] as int?) ?? 0) != 0,
      overtimePriceSnapshot: (map['overtime_price_snapshot'] as int?) ?? 0,
      overtimeMultiplier: (map['overtime_multiplier'] as int?) ?? 1000,
    );
  }

  final String id;

  /// `YYYY-MM-DD`，业务发生日期（锁账、结算按它归月）。
  final String date;

  /// 当天第几分钟（0..1439），业务发生时刻。
  ///
  /// 与 [date] 拼起来才是完整的发生时间；只用于排序与展示，
  /// 不参与任何金额计算，所以老数据缺省为 0 也不会算错钱。
  final int minuteOfDay;

  final String workerId;
  final String toyId;
  final String workerNameSnapshot;
  final String toyNameSnapshot;

  /// 工序快照，参与结算分组。
  final String processSnapshot;

  /// **正常班**单价快照，单位万分之一元。
  ///
  /// 加班时真正参与计算的是 [overtimePriceSnapshot]，
  /// 这里保留原价，方便工资条上同时显示「原价 / 加班价」。
  final int unitPriceSnapshot;

  final int quantity;

  /// 小计（分），逐笔取整后入库。
  final int subtotalCents;

  /// 是否加班。
  final bool overtime;

  /// 加班时的实际计价单价（万分之一元）。非加班为 0。
  final int overtimePriceSnapshot;

  /// 加班倍率（千分比，1500 = 1.5 倍），仅用于展示与审计。
  final int overtimeMultiplier;

  final String remark;

  /// NULL = 正常；非 NULL = 已删除（软删除，永不物理删除）。
  final int? deletedAt;

  final int createdAt;
  final int updatedAt;

  bool get isDeleted => deletedAt != null;

  /// [date] 的显式别名：业务日期（"哪一天的活"）。
  ///
  /// 统计、结算、锁账只看它；[createdAt] 永远不参与归集。
  /// 起这个名字是为了让调用处一眼分清两个时间字段。
  String get workDate => date;

  /// 录入时间（毫秒）所在的自然日，`YYYY-MM-DD`。
  String get createdAtDate => Dates.ymdOfMillis(createdAt);

  /// 录入时间，`YYYY-MM-DD HH:mm:ss`（审计展示用）。
  String get createdAtLabel => Dates.formatMillis(createdAt);

  /// 真正参与金额计算的那一个单价。
  ///
  /// 老数据 `overtime = false`，这里必然等于 [unitPriceSnapshot]，
  /// 所以升级前后金额完全一致。
  int get pricingPrice =>
      overtime && overtimePriceSnapshot > 0 ? overtimePriceSnapshot : unitPriceSnapshot;

  String get priceLabel => Money.formatPrice(unitPriceSnapshot);

  String get pricingPriceLabel => Money.formatPrice(pricingPrice);

  String get overtimeMultiplierLabel => Money.formatMultiplier(overtimeMultiplier);

  /// `14:42`，老数据回填的是录入时刻。
  String get timeLabel {
    final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get subtotalLabel => Money.formatCents(subtotalCents);

  PieceRecord copyWith({
    String? date,
    int? minuteOfDay,
    String? workerId,
    String? toyId,
    String? workerNameSnapshot,
    String? toyNameSnapshot,
    String? processSnapshot,
    int? unitPriceSnapshot,
    int? quantity,
    int? subtotalCents,
    bool? overtime,
    int? overtimePriceSnapshot,
    int? overtimeMultiplier,
    String? remark,
    int? deletedAt,
    bool clearDeletedAt = false,
    int? updatedAt,
  }) {
    return PieceRecord(
      id: id,
      date: date ?? this.date,
      minuteOfDay: minuteOfDay ?? this.minuteOfDay,
      workerId: workerId ?? this.workerId,
      toyId: toyId ?? this.toyId,
      workerNameSnapshot: workerNameSnapshot ?? this.workerNameSnapshot,
      toyNameSnapshot: toyNameSnapshot ?? this.toyNameSnapshot,
      processSnapshot: processSnapshot ?? this.processSnapshot,
      unitPriceSnapshot: unitPriceSnapshot ?? this.unitPriceSnapshot,
      quantity: quantity ?? this.quantity,
      subtotalCents: subtotalCents ?? this.subtotalCents,
      overtime: overtime ?? this.overtime,
      overtimePriceSnapshot: overtimePriceSnapshot ?? this.overtimePriceSnapshot,
      overtimeMultiplier: overtimeMultiplier ?? this.overtimeMultiplier,
      remark: remark ?? this.remark,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'minute_of_day': minuteOfDay,
        'worker_id': workerId,
        'toy_id': toyId,
        'worker_name_snapshot': workerNameSnapshot,
        'toy_name_snapshot': toyNameSnapshot,
        'process_snapshot': processSnapshot,
        'unit_price_snapshot': unitPriceSnapshot,
        'quantity': quantity,
        'subtotal_cents': subtotalCents,
        'overtime': overtime ? 1 : 0,
        'overtime_price_snapshot': overtimePriceSnapshot,
        'overtime_multiplier': overtimeMultiplier,
        'remark': remark,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
