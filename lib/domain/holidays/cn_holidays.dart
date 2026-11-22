/// 国内法定节假日 / 调休补班数据（仅用于界面标注，**不参与任何计算**）。
///
/// ## 维护方式
///
/// 每年国务院办公厅发布《关于 XXXX 年部分节假日安排的通知》后，
/// 只需在 [_ranges]（放假日）与 [_makeupWorkdays]（调休上班日）里
/// 按年份追加条目，**其余代码一行都不用改**。
///
/// ## 口径
///
/// * [HolidayKind.holiday]：法定放假日（含调休拼出来的连休日）；
/// * [HolidayKind.makeupWorkday]：被调休征用的周末"补班日"。
///   这两天最容易被误当成普通周末，所以单独标出来。
///
/// ## 降级
///
/// 查不到年份/日期时 [CnHolidays.of] 返回 `null`，界面按普通日期渲染，
/// 绝不影响记账、统计与结算。
library;

import '../../core/dates.dart';

/// 某一天的假期类型。
enum HolidayKind {
  /// 法定放假（含连休）。
  holiday,

  /// 调休上班（周末被征用）。
  makeupWorkday,
}

/// 一天的假期信息。
class CnHoliday {
  const CnHoliday({
    required this.date,
    required this.name,
    required this.kind,
  });

  /// `YYYY-MM-DD`。
  final String date;

  /// 节日名，如 `国庆节`、`春节`。
  final String name;

  final HolidayKind kind;

  bool get isHoliday => kind == HolidayKind.holiday;

  /// 角标文案：`休` / `班`。
  String get badge => isHoliday ? '休' : '班';

  /// 列表/日历里的一行说明：`国庆节放假` / `调休上班`。
  String get label => isHoliday ? '$name放假' : '调休上班（周末补班）';

  @override
  String toString() => 'CnHoliday($date, $name, ${kind.name})';
}

/// 一段连续放假区间。
class _HolidayRange {
  const _HolidayRange(this.start, this.end, this.name);

  final String start;
  final String end;
  final String name;
}

class CnHolidays {
  CnHolidays._();

  /// 放假日区间（起止均含）。
  ///
  /// 数据来源：国务院办公厅关于各年度部分节假日安排的通知。
  /// 2025-11-04 / 2024-11-12 / 2026-11-05 三次通知。
  static const List<_HolidayRange> _ranges = [
    // ---- 2025 ----
    _HolidayRange('2025-01-01', '2025-01-01', '元旦'),
    _HolidayRange('2025-01-28', '2025-02-04', '春节'),
    _HolidayRange('2025-04-04', '2025-04-06', '清明节'),
    _HolidayRange('2025-05-01', '2025-05-05', '劳动节'),
    _HolidayRange('2025-05-31', '2025-06-02', '端午节'),
    _HolidayRange('2025-10-01', '2025-10-08', '国庆节、中秋节'),
    // ---- 2026 ----
    _HolidayRange('2026-01-01', '2026-01-03', '元旦'),
    _HolidayRange('2026-02-15', '2026-02-23', '春节'),
    _HolidayRange('2026-04-04', '2026-04-06', '清明节'),
    _HolidayRange('2026-05-01', '2026-05-05', '劳动节'),
    _HolidayRange('2026-06-19', '2026-06-21', '端午节'),
    _HolidayRange('2026-09-25', '2026-09-27', '中秋节'),
    _HolidayRange('2026-10-01', '2026-10-07', '国庆节'),
    // ---- 2027 ----
    _HolidayRange('2027-01-01', '2027-01-03', '元旦'),
    _HolidayRange('2027-02-05', '2027-02-13', '春节'),
    _HolidayRange('2027-04-03', '2027-04-05', '清明节'),
    _HolidayRange('2027-05-01', '2027-05-05', '劳动节'),
    _HolidayRange('2027-06-09', '2027-06-09', '端午节'),
    _HolidayRange('2027-09-15', '2027-09-15', '中秋节'),
    _HolidayRange('2027-10-01', '2027-10-07', '国庆节'),
  ];

  /// 调休上班日（周末被征用），按年份分组只为读起来清楚。
  static const Map<int, List<String>> _makeupWorkdays = {
    2025: [
      '2025-01-26', // 春节调休
      '2025-02-08', // 春节调休
      '2025-04-27', // 劳动节调休
      '2025-09-28', // 国庆调休
      '2025-10-11', // 国庆调休
    ],
    2026: [
      '2026-01-04', // 元旦调休
      '2026-02-14', // 春节调休
      '2026-02-28', // 春节调休
      '2026-05-09', // 劳动节调休
      '2026-09-20', // 国庆调休
      '2026-10-10', // 国庆调休
    ],
    2027: [
      '2027-01-31', // 春节调休
      '2027-02-14', // 春节调休
      '2027-05-08', // 劳动节调休
      '2027-09-26', // 国庆调休
      '2027-10-09', // 国庆调休
    ],
  };

  /// `YYYY-MM-DD` → 假期信息。惰性建索引，只建一次。
  static final Map<String, CnHoliday> _index = _buildIndex();

  static Map<String, CnHoliday> _buildIndex() {
    final index = <String, CnHoliday>{};
    for (final range in _ranges) {
      // 直接按天推进，避免依赖 DateRange（它对非法区间会抛异常）
      final firstDay = Dates.tryParseYmd(range.start);
      final lastDay = Dates.tryParseYmd(range.end);
      if (firstDay == null || lastDay == null) continue;
      var cursor = firstDay;
      while (!cursor.isAfter(lastDay)) {
        final date = Dates.ymd(cursor);
        index[date] = CnHoliday(
          date: date,
          name: range.name,
          kind: HolidayKind.holiday,
        );
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
    }
    for (final entry in _makeupWorkdays.entries) {
      for (final date in entry.value) {
        index[date] = CnHoliday(
          date: date,
          name: '调休',
          kind: HolidayKind.makeupWorkday,
        );
      }
    }
    return index;
  }

  /// 有数据的年份（升序）。用于设置页/文档说明"标注覆盖到哪一年"。
  static final List<int> years = () {
    final set = <int>{
      for (final range in _ranges) int.parse(range.start.substring(0, 4)),
      ..._makeupWorkdays.keys,
    };
    final list = set.toList()..sort();
    return List<int>.unmodifiable(list);
  }();

  /// 查某天的假期信息；未配置的年份/日期返回 `null`（安全降级）。
  static CnHoliday? of(String ymd) {
    if (!Dates.isValidYmd(ymd)) return null;
    return _index[ymd];
  }

  /// 是否法定放假日。
  static bool isHoliday(String ymd) => of(ymd)?.isHoliday ?? false;

  /// 是否调休补班日。
  static bool isMakeupWorkday(String ymd) =>
      of(ymd)?.kind == HolidayKind.makeupWorkday;

  /// 角标文案：`休` / `班` / `null`。
  static String? badgeOf(String ymd) => of(ymd)?.badge;

  /// 完整说明：`国庆节放假` / `2026年调休调休上班`，无数据返回 `null`。
  static String? labelOf(String ymd) => of(ymd)?.label;

  /// 该年是否已配置（未配置时界面应避免任何"节假日"承诺）。
  static bool supportsYear(int year) => years.contains(year);
}
