import '../../core/constants.dart';
import '../../core/dates.dart';
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
    this.minuteOfDay = 0,
    this.workMinutes = 0,
    this.hourlyRateCents = 0,
    this.settledAt,
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
      minuteOfDay: (map['minute_of_day'] as int?) ?? 0,
      workMinutes: (map['work_minutes'] as int?) ?? 0,
      hourlyRateCents: (map['hourly_rate_cents'] as int?) ?? 0,
      settledAt: map['settled_at'] as int?,
    );
  }

  final String id;

  /// `YYYY-MM-DD`，业务日期：这笔调整项算哪一天的账。
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

  /// 当天第几分钟（0..1439），用于同日内排序与展示。
  final int minuteOfDay;

  /// 计时工资的工时（分钟）。0 表示「直接填金额」，不按工时算。
  final int workMinutes;

  /// 计时工资的时薪（分/小时）。0 表示未按工时算。
  final int hourlyRateCents;

  /// 单笔结算时间（毫秒），语义与 `PieceRecord.settledAt` 完全一致：
  /// `null` = 跟随整月标记；非空 = 这一笔已单独结算。
  final int? settledAt;

  /// 这一笔是否被单独标记为已结算。
  bool get settledIndividually => settledAt != null;

  /// 单独标记的结算时间，`YYYY-MM-DD HH:mm:ss`；未标记为 null。
  String? get settledAtLabel =>
      settledAt == null ? null : Dates.formatMillis(settledAt!);

  /// 综合整月标记判断这一笔是否已结算。
  bool isSettled(Set<String> settledMonths) =>
      settledAt != null || settledMonths.contains(Dates.ymOfYmd(date));

  /// 是否按「工时 × 时薪」计价（而不是直接填一个金额）。
  bool get isByWorkTime => workMinutes > 0 && hourlyRateCents > 0;

  /// [date] 的显式别名：业务日期（"这笔算哪一天的账"）。
  ///
  /// 与 [createdAt] 严格分开：改日期不会改录入时间，反之亦然。
  String get workDate => date;

  /// 录入时间（毫秒）所在的自然日，`YYYY-MM-DD`。
  String get createdAtDate => Dates.ymdOfMillis(createdAt);

  /// 录入时间，`YYYY-MM-DD HH:mm:ss`（审计展示用）。
  String get createdAtLabel => Dates.formatMillis(createdAt);

  /// 计时明细，例：`3.5 小时 × 25.00 元/时`；其它类型返回空串。
  String get workTimeLabel {
    if (!isByWorkTime) return '';
    return '${Money.formatHours(workMinutes)} 小时 × '
        '${Money.formatCents(hourlyRateCents)} 元/时';
  }

  /// 列表/工资条用的一句摘要：补贴显示名称，计时显示工时明细。
  String get summaryLabel {
    if (isByWorkTime) {
      return remark.isEmpty ? workTimeLabel : '$workTimeLabel · $remark';
    }
    return remark;
  }

  String get timeLabel {
    final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool get isDeleted => deletedAt != null;

  /// 计入应付的带符号金额（分）。
  int get signedCents => type.sign * amountCents;

  String get amountLabel => Money.formatCents(amountCents);

  Adjustment copyWith({
    String? date,
    int? minuteOfDay,
    int? workMinutes,
    int? hourlyRateCents,
    String? workerId,
    String? workerNameSnapshot,
    AdjustmentType? type,
    int? amountCents,
    String? remark,
    int? deletedAt,
    bool clearDeletedAt = false,
    int? settledAt,
    bool clearSettledAt = false,
    int? updatedAt,
  }) {
    return Adjustment(
      id: id,
      date: date ?? this.date,
      minuteOfDay: minuteOfDay ?? this.minuteOfDay,
      workMinutes: workMinutes ?? this.workMinutes,
      hourlyRateCents: hourlyRateCents ?? this.hourlyRateCents,
      workerId: workerId ?? this.workerId,
      workerNameSnapshot: workerNameSnapshot ?? this.workerNameSnapshot,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      remark: remark ?? this.remark,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
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
        'work_minutes': workMinutes,
        'hourly_rate_cents': hourlyRateCents,
        'remark': remark,
        'settled_at': settledAt,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'minute_of_day': minuteOfDay,
        'updated_at': updatedAt,
      };
}
