import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/domain/holidays/cn_holidays.dart';

/// 节假日表只做标注，但标注错了比没有更糟，所以逐条对着国务院通知验。
void main() {
  test('2026 年：元旦 / 春节 / 国庆的首尾都标对', () {
    // 元旦 1/1–1/3，1/4 补班
    expect(CnHolidays.isHoliday('2026-01-01'), isTrue);
    expect(CnHolidays.of('2026-01-03')?.name, '元旦');
    expect(CnHolidays.isMakeupWorkday('2026-01-04'), isTrue);
    expect(CnHolidays.isHoliday('2026-01-04'), isFalse);

    // 春节 2/15–2/23，2/14 与 2/28 补班
    expect(CnHolidays.isHoliday('2026-02-15'), isTrue);
    expect(CnHolidays.isHoliday('2026-02-23'), isTrue);
    expect(CnHolidays.isHoliday('2026-02-24'), isFalse);
    expect(CnHolidays.isMakeupWorkday('2026-02-14'), isTrue);
    expect(CnHolidays.isMakeupWorkday('2026-02-28'), isTrue);

    // 国庆 10/1–10/7，9/20 与 10/10 补班
    expect(CnHolidays.isHoliday('2026-10-01'), isTrue);
    expect(CnHolidays.of('2026-10-01')?.name, '国庆节');
    expect(CnHolidays.isHoliday('2026-10-07'), isTrue);
    expect(CnHolidays.isHoliday('2026-10-08'), isFalse);
    expect(CnHolidays.isMakeupWorkday('2026-09-20'), isTrue);
    expect(CnHolidays.isMakeupWorkday('2026-10-10'), isTrue);
  });

  test('2025 年：国庆中秋合并 8 天，前后补班', () {
    expect(CnHolidays.isHoliday('2025-10-01'), isTrue);
    expect(CnHolidays.isHoliday('2025-10-08'), isTrue);
    expect(CnHolidays.of('2025-10-08')?.name, '国庆节、中秋节');
    expect(CnHolidays.isMakeupWorkday('2025-09-28'), isTrue);
    expect(CnHolidays.isMakeupWorkday('2025-10-11'), isTrue);
    expect(CnHolidays.isHoliday('2025-01-01'), isTrue);
    expect(CnHolidays.isMakeupWorkday('2025-01-26'), isTrue);
  });

  test('2027 年：端午中秋只有一天，国庆 7 天', () {
    expect(CnHolidays.of('2027-06-09')?.name, '端午节');
    expect(CnHolidays.isHoliday('2027-06-09'), isTrue);
    expect(CnHolidays.isHoliday('2027-06-10'), isFalse);
    expect(CnHolidays.isHoliday('2027-09-15'), isTrue);
    expect(CnHolidays.isHoliday('2027-10-07'), isTrue);
    expect(CnHolidays.isHoliday('2027-10-08'), isFalse);
    expect(CnHolidays.isMakeupWorkday('2027-10-09'), isTrue);
  });

  test('普通工作日、未配置年份、非法日期都安全返回 null', () {
    expect(CnHolidays.of('2026-11-22'), isNull);
    expect(CnHolidays.isHoliday('2019-10-01'), isFalse);
    expect(CnHolidays.isMakeupWorkday('2019-10-12'), isFalse);
    expect(CnHolidays.of('2026-02-30'), isNull);
    expect(CnHolidays.of(''), isNull);
    expect(CnHolidays.badgeOf('2019-10-01'), isNull);
    expect(CnHolidays.labelOf('2019-10-01'), isNull);
    expect(CnHolidays.supportsYear(2019), isFalse);
  });

  test('角标与说明文案', () {
    final holiday = CnHolidays.of('2026-10-01')!;
    expect(holiday.badge, '休');
    expect(holiday.label, '国庆节放假');
    expect(holiday.kind, HolidayKind.holiday);

    final makeup = CnHolidays.of('2026-10-10')!;
    expect(makeup.badge, '班');
    expect(makeup.label, '调休上班（周末补班）');
    expect(makeup.kind, HolidayKind.makeupWorkday);
  });

  test('有数据的年份连续可用，便于维护时核对', () {
    expect(CnHolidays.years, containsAll(<int>[2025, 2026, 2027]));
    expect(CnHolidays.years, orderedEquals([...CnHolidays.years]..sort()));
    for (final year in CnHolidays.years) {
      expect(CnHolidays.supportsYear(year), isTrue);
    }
  });

  test('同一个日期不会既放假又补班', () {
    // 抽查所有已配置年份的 1 月与 10 月，避免维护时把补班日写进连休里
    for (final year in CnHolidays.years) {
      for (final month in [1, 2, 4, 5, 6, 9, 10]) {
        for (var day = 1; day <= 28; day++) {
          final ymd =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final info = CnHolidays.of(ymd);
          if (info == null) continue;
          expect(
            info.isHoliday != (info.kind == HolidayKind.makeupWorkday),
            isTrue,
            reason: '$ymd 的假期类型矛盾',
          );
        }
      }
    }
  });
}
