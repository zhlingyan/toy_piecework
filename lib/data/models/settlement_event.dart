import '../../core/dates.dart';

/// 结算状态变更的动作类型。
enum SettlementAction {
  settled('settled', '结算'),
  unsettled('unsettled', '取消结算');

  const SettlementAction(this.code, this.label);

  final String code;
  final String label;

  static SettlementAction fromCode(String code) =>
      code == SettlementAction.unsettled.code
          ? SettlementAction.unsettled
          : SettlementAction.settled;
}

/// 变更范围：整期（人 + 若干月份）/ 单笔（某一条流水或调整项）。
enum SettlementEventScope {
  range('range', '整期'),
  entry('entry', '单笔');

  const SettlementEventScope(this.code, this.label);

  final String code;
  final String label;

  static SettlementEventScope fromCode(String code) =>
      code == SettlementEventScope.entry.code
          ? SettlementEventScope.entry
          : SettlementEventScope.range;
}

/// 一条「追加」的状态变更历史。
///
/// 铁律：**只 INSERT，绝不 UPDATE / DELETE**。`seq` 是自增的追加标识（#1、#2…），
/// `happened_at` 是精确到秒的时间文本；每次变更都会生成新行，
/// 因此任何一次「已结算 / 取消已结算」的时间戳都不会被后来操作覆盖。
///
/// 当前状态仍由 `settlement_marks` + 流水 `settled_at` 决定（那两处会覆盖），
/// 历史表只负责审计留痕，两者刻意分离。
class SettlementEvent {
  const SettlementEvent({
    required this.seq,
    required this.workerId,
    required this.action,
    required this.scope,
    required this.reason,
    required this.months,
    required this.rangeStart,
    required this.rangeEnd,
    required this.entryLabel,
    required this.occurredAt,
    required this.happenedAt,
  });

  factory SettlementEvent.fromMap(Map<String, Object?> map) {
    final monthsText = map['months']?.toString() ?? '';
    final millis = (map['occurred_at'] as num?)?.toInt() ?? 0;
    final timeText = map['happened_at']?.toString() ?? '';
    return SettlementEvent(
      seq: (map['seq'] as num?)?.toInt() ?? 0,
      workerId: map['worker_id']?.toString() ?? '',
      action: SettlementAction.fromCode(map['action']?.toString() ?? 'settled'),
      scope: SettlementEventScope.fromCode(map['scope']?.toString() ?? 'range'),
      reason: map['reason']?.toString() ?? '',
      months: monthsText.isEmpty
          ? const []
          : monthsText.split(',').where((m) => m.isNotEmpty).toList(),
      rangeStart: map['range_start']?.toString() ?? '',
      rangeEnd: map['range_end']?.toString() ?? '',
      entryLabel: map['entry_label']?.toString() ?? '',
      occurredAt: millis,
      happenedAt: timeText.isNotEmpty && millis > 0
          ? timeText
          : (millis > 0 ? Dates.formatMillis(millis) : ''),
    );
  }

  /// 追加标识：`#12`。
  final int seq;
  final String workerId;
  final SettlementAction action;
  final SettlementEventScope scope;

  /// 取消理由（选填），结算操作为空串。
  final String reason;

  /// 整期涉及的月份（升序，逗号存库）。
  final List<String> months;
  final String rangeStart;
  final String rangeEnd;

  /// 单笔描述，如 `2026-11-05 · 计件流水`。
  final String entryLabel;

  /// 毫秒时间戳（排序 / 备份用）。
  final int occurredAt;

  /// `YYYY-MM-DD HH:mm:ss`（界面展示用）。
  final String happenedAt;

  Map<String, Object?> toMap() => {
        'seq': seq,
        'worker_id': workerId,
        'action': action.code,
        'scope': scope.code,
        'reason': reason,
        'months': months.join(','),
        'range_start': rangeStart,
        'range_end': rangeEnd,
        'entry_label': entryLabel,
        'occurred_at': occurredAt,
        'happened_at': happenedAt,
      };

  bool get isCancellation => action == SettlementAction.unsettled;
  bool get hasReason => reason.trim().isNotEmpty;
  String get signature => '#$seq';

  /// 精确到秒；老数据只有毫秒时也能兜底格式化。
  String get timeText => happenedAt;

  String get scopeText {
    if (scope == SettlementEventScope.entry) {
      return entryLabel.isEmpty ? '单笔' : entryLabel;
    }
    if (months.isEmpty) return '整期';
    return '整期 · ${months.join('、')}';
  }

  /// 历史面板里的次要说明。
  String get detailText {
    final parts = <String>[scopeText];
    if (scope == SettlementEventScope.range &&
        rangeStart.isNotEmpty &&
        rangeEnd.isNotEmpty) {
      parts.add('$rangeStart ~ $rangeEnd');
    }
    if (hasReason) parts.add('取消理由：${reason.trim()}');
    return parts.join(' · ');
  }
}
