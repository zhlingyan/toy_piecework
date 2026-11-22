import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/models/settlement.dart';
import '../common/ui_kit.dart';
import '../theme.dart';

/// 概览页「出勤人数」下钻：今日全员出勤名单。
///
/// 口径与 [DayOverview] 完全一致：
/// * 已出勤 = 当天有计件或调整项，正常高亮，附当日笔数 / 净额；
/// * 未出勤 = 当日在册但无记录，整行置灰 + 灰色徽标；
/// * 名单为空（还没建工人档案）走空态，不弹空白列表。
Future<void> showAttendanceSheet({
  required BuildContext context,
  required DayOverview overview,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AttendanceSheet(overview: overview),
  );
}

class _AttendanceSheet extends StatelessWidget {
  const _AttendanceSheet({required this.overview});

  final DayOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = overview.people;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DBE3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '今日出勤 · ${overview.date}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          MutedText(
                            '已出勤 ${overview.presentCount} 人 · '
                            '未出勤 ${overview.absentCount} 人 · '
                            '共 ${overview.totalWorkerCount} 人',
                          ),
                        ],
                      ),
                    ),
                    _AttendanceChip(
                      label: overview.attendanceLabel,
                      color: AppTheme.success,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDEFF3)),
              Expanded(
                child: people.isEmpty
                    ? const EmptyState(
                        title: '还没有工人档案',
                        hint: '到「设置 → 档案管理」添加工人后，这里会列出出勤与未出勤名单',
                        icon: Icons.person_off_outlined,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: people.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 72,
                          endIndent: 20,
                          color: Color(0xFFF0F2F6),
                        ),
                        itemBuilder: (context, index) =>
                            _PersonTile(person: people[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final AttendancePerson person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = person.present;
    final color = present ? AppTheme.success : const Color(0xFF9AA2AF);
    final greyText = const Color(0xFF9AA2AF);
    return ListTile(
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Text(
          person.name.isEmpty ? '?' : person.name.characters.first,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        person.displayName,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: present ? null : greyText,
          fontWeight: present ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        present
            ? '当日 ${person.recordCount} 笔 · ${Money.formatCents(person.netCents)} 元'
            : '今日暂无记录${person.isArchived ? ' · 已停用' : ''}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: present ? AppTheme.muted : const Color(0xFFB0B7C2),
        ),
      ),
      trailing: _AttendanceChip(
        label: present ? '已出勤' : '未出勤',
        color: color,
      ),
    );
  }
}

class _AttendanceChip extends StatelessWidget {
  const _AttendanceChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
