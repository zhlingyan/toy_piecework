import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../domain/holidays/cn_holidays.dart';
import '../../domain/rules/backfill_rules.dart';
import '../theme.dart';
import 'ui_kit.dart';

/// 「这笔是什么时候录进来的」详情。
///
/// 车间里最常吵的两句话是"这活是哪天干的"和"你这明明是今天才记的"。
/// 这个弹窗把两个时间摆在一起，谁都赖不掉：
/// * **归属日期 / 业务时刻**：统计与结算认的那一天；
/// * **录入时间**：精确到秒的保存时刻，改日期也不会变。
Future<void> showRecordTimeSheet(
  BuildContext context, {
  required String title,
  required String workDate,
  required int minuteOfDay,
  required int createdAt,
  int? updatedAt,
  String? remark,
  String? workerName,
}) {
  final today = Dates.ymd(AppClock.now());
  final holiday = CnHolidays.of(workDate);
  final backfill = BackfillRules.isBackfill(
    workDate: workDate,
    createdAtMillis: createdAt,
    today: today,
  );
  final daysEarlier = BackfillRules.daysEarlier(
    workDate: workDate,
    createdAtMillis: createdAt,
    today: today,
  );
  final createdDay = Dates.ymdOfMillis(createdAt);
  final createdDaysAgo = Dates.daysBetween(createdDay, today);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (backfill) ...[
                InfoBanner(
                  text: '这是今天补录的记录：账算在 $workDate，录入时间是今天。'
                      '统计和结算都按「归属日期」走，不会算到今天。',
                  color: AppTheme.danger,
                  icon: Icons.history,
                ),
                const SizedBox(height: 10),
              ],
              KeyValueRow(
                label: '归属日期',
                value: '$workDate ${Dates.weekdayLabel(workDate)}'.trim(),
                bold: true,
              ),
              KeyValueRow(
                label: '业务时刻',
                value: Dates.hhmm(minuteOfDay),
              ),
              if (holiday != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          '当天性质',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.muted),
                        ),
                      ),
                      HolidayBadge(holiday),
                    ],
                  ),
                ),
              const Divider(height: 18),
              KeyValueRow(
                label: '录入时间',
                value: Dates.formatMillis(createdAt),
                valueColor: backfill ? AppTheme.danger : null,
                bold: backfill,
              ),
              KeyValueRow(
                label: '录入日期',
                value: createdDaysAgo == 0 ? '$createdDay（今天）' : '$createdDay（$createdDaysAgo 天前）',
              ),
              if (updatedAt != null && updatedAt != createdAt)
                KeyValueRow(
                  label: '最近修改',
                  value: Dates.formatMillis(updatedAt),
                ),
              if (workerName != null && workerName.isNotEmpty)
                KeyValueRow(label: '工人', value: workerName),
              if (remark != null && remark.isNotEmpty)
                KeyValueRow(label: '备注', value: remark),
              if (daysEarlier != null) ...[
                const SizedBox(height: 6),
                Text(
                  '比今天早 $daysEarlier 天录入，所以标了「补录」。'
                  '按哪一个日期统计，完全取决于「归属日期」这一栏。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}
