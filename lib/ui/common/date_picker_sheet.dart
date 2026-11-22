import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../theme.dart';
import 'ui_kit.dart';

/// 选记账日期（业务日期）。
///
/// 为什么不用系统 `showDatePicker`：它无法在某一天上挂角标，
/// 而车间排班最需要一眼看出"哪天放假、哪天调休要上班"。
/// 这里自己画一个 7 列日历，节假日数据来自 [CnHolidays]，
/// 未配置的年份按普通日期显示，不加任何标注。
///
/// 返回 `YYYY-MM-DD`；取消返回 `null`。
Future<String?> pickRecordDate(
  BuildContext context, {
  required String initial,
  String title = '选择记账日期',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _DatePickerSheet(
      initial: initial,
      title: title,
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({required this.initial, required this.title});

  final String initial;
  final String title;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  static const List<String> _weekHeaders = ['一', '二', '三', '四', '五', '六', '日'];

  late DateTime _visibleMonth;
  late String _selected;

  /// 可选范围：2018-01-01 ~ 明天（保留"夜里跨零点记上一班"的余地）。
  static final DateTime _minDate = DateTime(2018, 1, 1);

  DateTime get _maxDate {
    final now = Dates.dateOnly(AppClock.now());
    return DateTime(now.year, now.month, now.day + 1);
  }

  @override
  void initState() {
    super.initState();
    final parsed = Dates.tryParseYmd(widget.initial) ??
        Dates.dateOnly(AppClock.now());
    _selected = Dates.ymd(parsed);
    _visibleMonth = DateTime(parsed.year, parsed.month, 1);
  }

  bool _canGoPrev() =>
      DateTime(_visibleMonth.year, _visibleMonth.month, 1).isAfter(_minDate);

  bool _canGoNext() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    return !next.isAfter(DateTime(_maxDate.year, _maxDate.month, 1));
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    if (next.isBefore(DateTime(_minDate.year, _minDate.month, 1))) return;
    if (next.isAfter(DateTime(_maxDate.year, _maxDate.month, 1))) return;
    setState(() => _visibleMonth = next);
  }

  void _pick(String ymd) => Navigator.of(context).pop(ymd);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDate = Dates.tryParseYmd(_selected);
    final selectedHoliday = CnHolidays.of(_selected);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5D9E0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
            // 已选日期 + 当天的假期说明，避免选完才知道是放假
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  selectedDate == null
                      ? _selected
                      : '$_selected ${Dates.weekdayLabel(_selected)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                if (selectedHoliday != null)
                  HolidayBadge(selectedHoliday, compact: true)
                else if (CnHolidays.supportsYear(selectedDate?.year ?? 0))
                  Text(
                    '${Dates.weekdayLabel(_selected)} · 工作日',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.muted),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _buildMonthHeader(theme),
            const SizedBox(height: 6),
            _buildWeekHeader(theme),
            const SizedBox(height: 4),
            _buildGrid(theme),
            const SizedBox(height: 12),
            _buildLegend(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader(ThemeData theme) {
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: _canGoPrev() ? () => _shiftMonth(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            Dates.monthLabel(Dates.ym(_visibleMonth)),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: _canGoNext() ? () => _shiftMonth(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 4),
        // 昨天是补录最常见的场景，给一个一键入口
        TextButton(
          onPressed: () {
            final now = Dates.dateOnly(AppClock.now());
            final yesterday = DateTime(now.year, now.month, now.day - 1);
            // 超出可录范围（2018 年以前）就不响应，避免绕过校验
            if (yesterday.isBefore(_minDate)) return;
            _pick(Dates.ymd(yesterday));
          },
          child: const Text('昨天'),
        ),
        TextButton(
          onPressed: () => _pick(Dates.ymd(Dates.dateOnly(AppClock.now()))),
          child: const Text('今天'),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(ThemeData theme) {
    return Row(
      children: [
        for (final header in _weekHeaders)
          Expanded(
            child: Center(
              child: Text(
                header,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(ThemeData theme) {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final firstWeekday = DateTime(year, month, 1).weekday; // 周一=1
    final days = Dates.daysInMonth(year, month);

    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const Expanded(child: SizedBox(height: 54)));
    }
    for (var day = 1; day <= days; day++) {
      final date = DateTime(year, month, day);
      final ymd = Dates.ymd(date);
      cells.add(
        Expanded(
          child: _buildDayCell(
            theme,
            date: date,
            ymd: ymd,
            enabled: !date.isAfter(_maxDate),
          ),
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox(height: 54)));
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 7 < cells.length ? 2 : 0),
          child: Row(children: cells.sublist(i, i + 7)),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(
    ThemeData theme, {
    required DateTime date,
    required String ymd,
    required bool enabled,
  }) {
    final holiday = CnHolidays.of(ymd);
    final selected = ymd == _selected;
    final isToday = ymd == Dates.ymd(Dates.dateOnly(AppClock.now()));

    Color foreground;
    Color? background;
    if (selected) {
      foreground = Colors.white;
      background = AppTheme.primary;
    } else if (!enabled) {
      foreground = AppTheme.muted.withValues(alpha: 0.35);
    } else if (holiday != null && holiday.isHoliday) {
      foreground = AppTheme.warning;
      background = AppTheme.warning.withValues(alpha: 0.10);
    } else if (holiday != null) {
      // 调休上班：用主色轻微打底，和"放假"的暖色区分开
      foreground = AppTheme.primary;
      background = AppTheme.primary.withValues(alpha: 0.06);
    } else {
      foreground = const Color(0xFF1B2430);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: [
        ymd,
        Dates.weekdayLabel(ymd),
        if (holiday != null) holiday.label,
      ].join(' '),
      child: InkWell(
        onTap: enabled ? () => _pick(ymd) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 54,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !selected
                ? Border.all(color: AppTheme.primary.withValues(alpha: 0.6), width: 1.5)
                : null,
          ),
          child: Center(
            // FittedBox 兜底：大字模式下日期 + 角标也绝不撑破格子
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 42,
                height: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (holiday != null)
                      Text(
                        holiday.badge,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : (holiday.isHoliday
                                  ? AppTheme.warning
                                  : AppTheme.primary),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(ThemeData theme) {
    final years = CnHolidays.years;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _legendItem(theme, '休', '法定假期', AppTheme.warning),
              _legendItem(theme, '班', '调休上班', AppTheme.primary),
              Text(
                '角标只是提醒，不影响任何金额计算',
                style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
              ),
            ],
          ),
          if (years.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '假期数据覆盖 ${years.first}–${years.last} 年，其它年份按普通日期显示',
              style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendItem(ThemeData theme, String badge, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
