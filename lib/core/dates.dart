/// 日期工具：数据库内统一用 `YYYY-MM-DD` 文本存储，便于字符串比较与索引。
class Dates {
  Dates._();

  static String ymd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String ym(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// 严格校验 `YYYY-MM-DD`，并拒绝 2026-02-30 这类不存在的日期。
  static DateTime? tryParseYmd(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final y = int.parse(value.substring(0, 4));
    final m = int.parse(value.substring(5, 7));
    final d = int.parse(value.substring(8, 10));
    if (m < 1 || m > 12) return null;
    if (d < 1 || d > daysInMonth(y, m)) return null;
    return DateTime(y, m, d);
  }

  static bool isValidYmd(String value) => tryParseYmd(value) != null;

  /// 严格校验 `YYYY-MM`。
  static bool isValidYm(String value) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) return false;
    final m = int.parse(value.substring(5, 7));
    return m >= 1 && m <= 12;
  }

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// 从 `YYYY-MM-DD` 取出 `YYYY-MM`。
  static String ymOfYmd(String ymd) => ymd.substring(0, 7);

  /// 取某月最后一天的 `YYYY-MM-DD`。
  static String lastDayOfYm(String ym) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    return ymd(DateTime(y, m, daysInMonth(y, m)));
  }

  static String firstDayOfYm(String ym) => '$ym-01';

  /// 前后平移若干天（跨月、跨年、闰年均由 DateTime 处理）。
  static String addDays(String ymdValue, int days) {
    final d = tryParseYmd(ymdValue);
    if (d == null) throw ArgumentError('非法日期: $ymdValue');
    return ymd(DateTime(d.year, d.month, d.day + days));
  }

  /// 判断两个月份是否相邻或相同（用于结算页快捷区间提示，无则返回 false）。
  static int compareYmd(String a, String b) => a.compareTo(b);

  // ---- 时分（精确到分钟）----
  //
  // 只存「当天第几分钟」(0..1439)，不存时间戳：
  // 它不带时区、不受夏令时影响、能直接参与字符串/整数排序，
  // 且与已有的 `date` 列拼起来就是完整的业务发生时间。

  /// 一天的总分钟数。
  static const int minutesPerDay = 24 * 60;

  /// 取当前时刻是当天第几分钟。
  static int minuteOfDay(DateTime time) => time.hour * 60 + time.minute;

  /// 把分钟数格式化为 `HH:mm`，越界自动收敛到当天范围内。
  static String hhmm(int minuteOfDay) {
    final m = minuteOfDay.clamp(0, minutesPerDay - 1);
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  /// `HH:mm` 形式的展示，附带「上午/下午」可读性（列表里用）。
  static String hhmmLabel(int minuteOfDay) => hhmm(minuteOfDay);

  static const List<String> _weekdayLabels = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// `YYYY-MM-DD` → `周三`。日期非法时返回空串，界面自行决定怎么兜底。
  static String weekdayLabel(String value) {
    final date = tryParseYmd(value);
    if (date == null) return '';
    return _weekdayLabels[date.weekday - 1];
  }

  /// 把 `YYYY-MM-DD` + 分钟数合成为 `DateTime`，用于日期+时间选择器。
  static DateTime combine(String ymdValue, int minuteOfDay) {
    final d = tryParseYmd(ymdValue);
    if (d == null) throw ArgumentError('非法日期: $ymdValue');
    final m = minuteOfDay.clamp(0, minutesPerDay - 1);
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  /// 从 `DateTime` 取出 `(YYYY-MM-DD, 分钟)`。
  static ({String date, int minute}) split(DateTime time) =>
      (date: ymd(time), minute: minuteOfDay(time));
}

/// 结算/查询区间，起止均为**闭区间**（含边界）。
class DateRange implements Comparable<DateRange> {
  const DateRange({required this.start, required this.end});

  /// 起止日期，格式 `YYYY-MM-DD`。
  final String start;
  final String end;

  factory DateRange.of(String start, String end) {
    if (!Dates.isValidYmd(start) || !Dates.isValidYmd(end)) {
      throw ArgumentError('日期格式错误: $start ~ $end');
    }
    if (start.compareTo(end) > 0) {
      throw ArgumentError('开始日期不能晚于结束日期');
    }
    return DateRange(start: start, end: end);
  }

  factory DateRange.day(DateTime now) {
    final d = Dates.ymd(now);
    return DateRange(start: d, end: d);
  }

  /// 近 7 天，含当天。
  factory DateRange.last7Days(DateTime now) {
    final today = Dates.dateOnly(now);
    final begin = DateTime(today.year, today.month, today.day - 6);
    return DateRange(start: Dates.ymd(begin), end: Dates.ymd(today));
  }

  factory DateRange.thisMonth(DateTime now) {
    final ym = Dates.ym(now);
    return DateRange(start: Dates.firstDayOfYm(ym), end: Dates.lastDayOfYm(ym));
  }

  factory DateRange.lastMonth(DateTime now) {
    final firstOfThis = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(firstOfThis.year, firstOfThis.month - 1, 1);
    final ym = Dates.ym(lastMonth);
    return DateRange(start: Dates.firstDayOfYm(ym), end: Dates.lastDayOfYm(ym));
  }

  factory DateRange.month(String ym) {
    if (!Dates.isValidYm(ym)) throw ArgumentError('月份格式错误: $ym');
    return DateRange(start: Dates.firstDayOfYm(ym), end: Dates.lastDayOfYm(ym));
  }

  bool contains(String ymd) => ymd.compareTo(start) >= 0 && ymd.compareTo(end) <= 0;

  /// 区间覆盖的月份列表，锁账校验需要。
  List<String> get months {
    final result = <String>[];
    var cursor = DateTime.parse(start);
    final last = DateTime.parse(end);
    while (!cursor.isAfter(last)) {
      final key = Dates.ym(cursor);
      if (result.isEmpty || result.last != key) result.add(key);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return result;
  }

  int get dayCount =>
      DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;

  Iterable<String> get days sync* {
    var cursor = DateTime.parse(start);
    final last = DateTime.parse(end);
    while (!cursor.isAfter(last)) {
      yield Dates.ymd(cursor);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
  }

  String get label => start == end ? start : '$start ~ $end';

  @override
  int compareTo(DateRange other) => start.compareTo(other.start);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start ~ $end)';
}
