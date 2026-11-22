import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/domain/rules/date_periods.dart';

/// 区间口径必须能背下来：周一到周日、自然月、自然季度、自然半年。
///
/// 全部用固定日期算，避免"今天跑测试"影响结果。
void main() {
  /// 2026-11-22 是周日（下半年、Q4）。
  final sunday = DateTime(2026, 11, 22);

  PeriodOption optionOf(List<PeriodGroup> groups, String key) {
    for (final group in groups) {
      for (final option in group.options) {
        if (option.key == key) return option;
      }
    }
    fail('没有 $key 这个区间');
  }

  test('五组区间，共 10 个选项', () {
    final groups = DatePeriods.groups(sunday);
    expect(groups.map((g) => g.title).toList(), ['周', '月', '季度', '半年', '年']);
    expect(DatePeriods.all(sunday).length, 10);
  });

  test('周：周一到周日，上周紧挨着本周', () {
    final groups = DatePeriods.groups(sunday);
    final thisWeek = optionOf(groups, 'this-week');
    expect(thisWeek.range.start, '2026-11-16'); // 周一
    expect(thisWeek.range.end, '2026-11-22'); // 周日
    expect(Dates.weekdayLabel(thisWeek.range.start), '周一');
    expect(Dates.weekdayLabel(thisWeek.range.end), '周日');

    final lastWeek = optionOf(groups, 'last-week');
    expect(lastWeek.range.start, '2026-11-09');
    expect(lastWeek.range.end, '2026-11-15');
  });

  test('月：自然月首尾', () {
    final groups = DatePeriods.groups(sunday);
    expect(optionOf(groups, 'this-month').range.start, '2026-11-01');
    expect(optionOf(groups, 'this-month').range.end, '2026-11-30');
    expect(optionOf(groups, 'last-month').range.start, '2026-10-01');
    expect(optionOf(groups, 'last-month').range.end, '2026-10-31');
  });

  test('季度：Q4 / Q3，跨年也不出错', () {
    final groups = DatePeriods.groups(sunday);
    final thisQuarter = optionOf(groups, 'this-quarter');
    expect(thisQuarter.range.start, '2026-10-01');
    expect(thisQuarter.range.end, '2026-12-31');
    expect(thisQuarter.note, 'Q4');

    final lastQuarter = optionOf(groups, 'last-quarter');
    expect(lastQuarter.range.start, '2026-07-01');
    expect(lastQuarter.range.end, '2026-09-30');
    expect(lastQuarter.note, 'Q3');

    // Q1 的"上个季度"要回到上一年 Q4
    final february = DatePeriods.groups(DateTime(2026, 2, 10));
    final crossYear = optionOf(february, 'last-quarter');
    expect(crossYear.range.start, '2025-10-01');
    expect(crossYear.range.end, '2025-12-31');
    expect(crossYear.note, 'Q4');
  });

  test('半年：下半年时"这半年"是 7–12 月，与"上半年"不同', () {
    final groups = DatePeriods.groups(sunday);
    final thisHalf = optionOf(groups, 'this-half');
    expect(thisHalf.range.start, '2026-07-01');
    expect(thisHalf.range.end, '2026-12-31');
    expect(thisHalf.note, '当前所在半年（7–12 月）');

    final firstHalf = optionOf(groups, 'first-half');
    expect(firstHalf.range.start, '2026-01-01');
    expect(firstHalf.range.end, '2026-06-30');
    expect(firstHalf.note, '当年 1–6 月');
    expect(thisHalf.range, isNot(firstHalf.range));
  });

  test('半年：上半年时"这半年"就是 1–6 月，说明里写清楚', () {
    final march = DatePeriods.groups(DateTime(2026, 3, 10));
    final thisHalf = optionOf(march, 'this-half');
    final firstHalf = optionOf(march, 'first-half');
    expect(thisHalf.range.start, '2026-01-01');
    expect(thisHalf.range.end, '2026-06-30');
    expect(thisHalf.range, firstHalf.range);
    expect(thisHalf.note, contains('与「上半年」相同'));
  });

  test('年：自然年，上一年完整覆盖', () {
    final groups = DatePeriods.groups(sunday);
    expect(optionOf(groups, 'this-year').range.start, '2026-01-01');
    expect(optionOf(groups, 'this-year').range.end, '2026-12-31');
    expect(optionOf(groups, 'last-year').range.start, '2025-01-01');
    expect(optionOf(groups, 'last-year').range.end, '2025-12-31');
  });

  test('副标题同时给出起止日期与口径说明', () {
    final options = DatePeriods.all(sunday);
    final thisMonth = options.firstWhere((o) => o.key == 'this-month');
    expect(thisMonth.subtitle, '2026-11-01 ~ 2026-11-30');

    final thisHalf = options.firstWhere((o) => o.key == 'this-half');
    expect(thisHalf.subtitle, contains('2026-07-01 ~ 2026-12-31'));
    expect(thisHalf.subtitle, contains('7–12 月'));
  });

  test('当前区间能回显名称，自定义区间识别为「自定义」', () {
    expect(DatePeriods.match(DateRange.thisMonth(sunday), sunday)?.label, '这个月');
    expect(
      DatePeriods.labelOf(
        const DateRange(start: '2026-11-03', end: '2026-11-09'),
        sunday,
      ),
      '自定义',
    );
    expect(
      DatePeriods.noteOf(
        const DateRange(start: '2026-11-03', end: '2026-11-09'),
        sunday,
      ),
      isNull,
    );
  });

  test('每条区间都是合法闭区间且 start <= end', () {
    for (final option in DatePeriods.all(sunday)) {
      expect(
        option.range.start.compareTo(option.range.end) <= 0,
        isTrue,
        reason: '${option.key} 的起止颠倒了',
      );
      expect(Dates.isValidYmd(option.range.start), isTrue);
      expect(Dates.isValidYmd(option.range.end), isTrue);
    }
  });
}
