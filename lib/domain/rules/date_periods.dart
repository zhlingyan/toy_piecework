import '../../core/dates.dart';

/// 一个可选的时间区间。
///
/// [note] 专门用来消除口径歧义（尤其"这半年"与"上半年"），
/// 界面上会把它和起止日期一起显示，避免用户凭感觉猜。
class PeriodOption {
  const PeriodOption({
    required this.key,
    required this.label,
    required this.range,
    this.note,
  });

  /// 稳定标识（`this-week` / `this-half` …），用于回显"当前选的是哪个"。
  final String key;
  final String label;
  final DateRange range;
  final String? note;

  /// 副标题：`2026-11-01 ~ 2026-11-30` 或 `2026-11-01 ~ 2026-11-30 · 周一到周日`。
  String get subtitle =>
      note == null ? Dates.rangeLabel(range.start, range.end) : '${Dates.rangeLabel(range.start, range.end)} · $note';

  @override
  String toString() => 'PeriodOption($key, ${range.label})';
}

/// 一组区间（周 / 月 / 季度 / 半年 / 年）。
class PeriodGroup {
  const PeriodGroup({required this.title, required this.options});

  final String title;
  final List<PeriodOption> options;
}

/// 自然日历区间表：周、月、季度、半年、年。
///
/// ## 口径（写死在代码里，也写在界面上）
///
/// * **周**：周一到周日（国内习惯，不是周日到周六）；
/// * **月**：自然月，1 号到月末；
/// * **季度**：自然季度 Q1(1–3) / Q2(4–6) / Q3(7–9) / Q4(10–12)；
/// * **半年**：「这半年」= 当前**所在**的自然半年（1–6 月或 7–12 月），
///   「上半年」= 当年 1–6 月。当前在上半年时两者完全相同，
///   [PeriodOption.note] 会明确写出来，不做模糊处理；
/// * **年**：自然年 1 月 1 日到 12 月 31 日。
///
/// 所有区间都是**闭区间**，与结算查询、锁账校验的语义一致。
class DatePeriods {
  DatePeriods._();

  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  static PeriodOption _option(
    String key,
    String label,
    DateTime start,
    DateTime end, {
    String? note,
  }) {
    return PeriodOption(
      key: key,
      label: label,
      range: DateRange.of(Dates.ymd(start), Dates.ymd(end)),
      note: note,
    );
  }

  /// 按周期层级分好组的完整区间表。
  static List<PeriodGroup> groups(DateTime now) {
    final today = Dates.dateOnly(now);
    final year = today.year;
    final month = today.month;

    // 周：周一起算
    final monday = _addDays(today, -(today.weekday - 1));
    final lastMonday = _addDays(monday, -7);

    // 季度：Q1..Q4
    final quarter = (month - 1) ~/ 3;
    final quarterStartMonth = quarter * 3 + 1;
    final lastQuarterStart = DateTime(year, quarterStartMonth - 3, 1);

    // 半年：当前所在半年 vs 当年 1–6 月
    final inFirstHalf = month <= 6;
    final halfStartMonth = inFirstHalf ? 1 : 7;

    return [
      PeriodGroup(
        title: '周',
        options: [
          _option(
            'this-week',
            '本周',
            monday,
            _addDays(monday, 6),
            note: '周一到周日',
          ),
          _option(
            'last-week',
            '上周',
            lastMonday,
            _addDays(monday, -1),
            note: '周一到周日',
          ),
        ],
      ),
      PeriodGroup(
        title: '月',
        options: [
          _option(
            'this-month',
            '这个月',
            DateTime(year, month, 1),
            DateTime(year, month, Dates.daysInMonth(year, month)),
          ),
          _option(
            'last-month',
            '上个月',
            DateTime(year, month - 1, 1),
            DateTime(year, month, 0),
          ),
        ],
      ),
      PeriodGroup(
        title: '季度',
        options: [
          _option(
            'this-quarter',
            '这个季度',
            DateTime(year, quarterStartMonth, 1),
            DateTime(year, quarterStartMonth + 3, 0),
            note: 'Q${quarter + 1}',
          ),
          _option(
            'last-quarter',
            '上个季度',
            lastQuarterStart,
            DateTime(lastQuarterStart.year, lastQuarterStart.month + 3, 0),
            note: 'Q${((lastQuarterStart.month - 1) ~/ 3) + 1}',
          ),
        ],
      ),
      PeriodGroup(
        title: '半年',
        options: [
          _option(
            'this-half',
            '这半年',
            DateTime(year, halfStartMonth, 1),
            DateTime(year, halfStartMonth + 6, 0),
            note: inFirstHalf
                ? '当前在上半年，与「上半年」相同（1–6 月）'
                : '当前所在半年（7–12 月）',
          ),
          _option(
            'first-half',
            '上半年',
            DateTime(year, 1, 1),
            DateTime(year, 7, 0),
            note: '当年 1–6 月',
          ),
        ],
      ),
      PeriodGroup(
        title: '年',
        options: [
          _option(
            'this-year',
            '这一年',
            DateTime(year, 1, 1),
            DateTime(year, 12, 31),
            note: '当年 1–12 月',
          ),
          _option(
            'last-year',
            '上一年',
            DateTime(year - 1, 1, 1),
            DateTime(year - 1, 12, 31),
            note: '${year - 1} 年 1–12 月',
          ),
        ],
      ),
    ];
  }

  /// 拍平后的全部区间，便于查找。顺序与 [groups] 一致。
  static List<PeriodOption> all(DateTime now) => [
        for (final group in groups(now)) ...group.options,
      ];

  /// 找出与 [range] 完全匹配的区间；没有则返回 `null`（说明是自定义）。
  static PeriodOption? match(DateRange range, DateTime now) {
    for (final option in all(now)) {
      if (option.range == range) return option;
    }
    return null;
  }

  /// 当前区间的显示名：命中预设返回 `本月`，否则 `自定义`。
  static String labelOf(DateRange range, DateTime now) =>
      match(range, now)?.label ?? '自定义';

  /// 当前区间的口径说明；自定义区间返回 `null`。
  static String? noteOf(DateRange range, DateTime now) =>
      match(range, now)?.note;

  /// 默认区间：本月。
  static DateRange defaultRange(DateTime now) => DateRange.thisMonth(now);
}
