import '../../core/dates.dart';
import 'adjustment.dart';
import 'piece_record.dart';
import 'settlement_mark.dart';

/// 结算状态的**唯一数据源快照**。
///
/// 判定口径与 `SettlementRepository.settle()` 的 LEFT JOIN 完全一致：
/// 一笔账「已结算」当且仅当
/// * 它自己的 `settled_at` 非空（逐笔结算）；或
/// * 它所属的 `workerId|month` 在 `settlement_marks` 里被整月标记。
///
/// 之前计数页把「该月已结算的工人 id 集合」当成「月份集合」传给
/// `PieceRecord.isSettled`，导致整月标记的账在计数页永远显示未结算；
/// 明细页、下钻页又各自用单人月份集合，两页口径分叉。
/// 现在所有页面都从 [SettlementMarkRepository.loadState] 取这一份快照，
/// 再用 [isPieceSettled] / [isAdjustmentSettled] 判定，杜绝各读各的。
class SettlementState {
  const SettlementState(this.settledMarkKeys);

  /// 空快照：任何一笔都未整月结算（仍可能靠自身 `settled_at` 已结）。
  static const empty = SettlementState(<String>{});

  /// `workerId|month` 组合键集合，来自 `settlement_marks.is_settled = 1`。
  final Set<String> settledMarkKeys;

  /// 某个「工人 + 月份」是否已整月标记结算。
  bool isMarkSettled(String workerId, String month) =>
      settledMarkKeys.contains(SettlementMark.keyOf(workerId, month));

  /// 底层判定：逐笔已结 OR 整月已结。
  bool isSettled({
    required String workerId,
    required String workDate,
    required int? settledAt,
  }) =>
      settledAt != null ||
      settledMarkKeys.contains(
        SettlementMark.keyOf(workerId, Dates.ymOfYmd(workDate)),
      );

  bool isPieceSettled(PieceRecord record) => isSettled(
        workerId: record.workerId,
        workDate: record.date,
        settledAt: record.settledAt,
      );

  bool isAdjustmentSettled(Adjustment adjustment) => isSettled(
        workerId: adjustment.workerId,
        workDate: adjustment.date,
        settledAt: adjustment.settledAt,
      );
}
