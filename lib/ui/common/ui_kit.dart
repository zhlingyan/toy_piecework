import 'package:material_ui/material_ui.dart';

import '../../domain/holidays/cn_holidays.dart';
import '../../domain/rules/settlement_rules.dart';
import '../theme.dart';

/// 白底圆角卡片，统一页面骨架。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.titleWidget,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  final String? title;

  /// 自定义标题（如「日期 + 假期角标」）。给了它就不用 [title]。
  final Widget? titleWidget;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    // 背景色必须由 Material 提供：卡片里会放 ListTile / SwitchListTile，
    // 如果外层用带背景色的 Container，Flutter 会报「水波纹被遮挡」的错误。
    // 因此外层只负责阴影（无颜色），内层 Material 负责底色与裁剪。
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppTheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null || titleWidget != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: titleWidget ??
                            Text(
                              title ?? '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 概览页大号数字块。
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final IconData? icon;

  /// 给了就变成可点击卡片（如水波纹 + 右侧箭头），用于下钻名单。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? AppTheme.primary;
    final radius = BorderRadius.circular(16);
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: radius,
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 30,
                    ),
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    // 水波纹必须由 Material 提供：Container 自带底色会遮住 InkWell 的涟漪，
    // 所以外层用透明 Material，底色留在内层 Container。
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      ),
    );
  }
}

/// 一行「标签 - 值」，用于明细。
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: valueColor,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 46, color: const Color(0xFFB6BDC9)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.muted),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 提示条（锁账、回收站超期等）。
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.color = AppTheme.primary,
    this.icon = Icons.info_outline,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 二次确认弹窗：高危操作统一走这里。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 17, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : const Color(0xFF263238),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
}

/// 空数据提示用的小字。
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.muted,
            height: 1.5,
          ),
    );
  }
}

/// 法定假期 / 调休补班角标。
///
/// 暖色 = 放假（和"加班"用同一种暖色，语义都是"这天不一样"），
/// 蓝色 = 调休上班。故意做成两种颜色：车间里最容易搞错的是
/// "周末要上班"的调休日，如果也涂成"休息色"就会误导排班。
///
/// 纯展示：不参与任何金额计算。
class HolidayBadge extends StatelessWidget {
  const HolidayBadge(
    this.holiday, {
    super.key,
    this.compact = false,
    this.showName = true,
  });

  final CnHoliday holiday;
  final bool compact;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final color = holiday.isHoliday ? AppTheme.warning : AppTheme.primary;
    final text = holiday.isHoliday
        ? (showName ? '${holiday.name} · 休' : '休')
        : (showName ? '调休上班' : '班');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              holiday.isHoliday ? Icons.beach_access : Icons.work_outline,
              size: compact ? 11 : 13,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「补录」角标：今天录入、记到更早的业务日期。
///
/// 红色是刻意的——这是唯一一种会让人怀疑"账记错日子"的记录，
/// 必须比加班/结算这些小标签更扎眼。
class BackfillBadge extends StatelessWidget {
  const BackfillBadge({super.key, this.daysEarlier, this.compact = false});

  /// 提前了几天；为 null 时只显示「补录」。
  final int? daysEarlier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = daysEarlier == null ? '补录' : '补录 $daysEarlier 天';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: compact ? 11 : 13,
              color: AppTheme.danger,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: AppTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结算状态标签：已结算 / 部分已结 / 未结算。
///
/// 颜色语义固定：绿=已结清，橙=还有钱没发，蓝=跨月只结了一部分。
/// 明细页里用 [compact] 缩小一号，避免一屏几十条时标签比内容还抢眼。
class SettlementBadge extends StatelessWidget {
  const SettlementBadge(this.status, {super.key, this.compact = false});

  final SettlementStatus status;
  final bool compact;

  Color get _color => switch (status) {
        SettlementStatus.settled => AppTheme.success,
        SettlementStatus.partial => AppTheme.primary,
        SettlementStatus.unsettled => AppTheme.warning,
      };

  IconData get _icon => switch (status) {
        SettlementStatus.settled => Icons.check_circle_outline,
        SettlementStatus.partial => Icons.timelapse,
        SettlementStatus.unsettled => Icons.schedule,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    // FittedBox 兜底：标签常被塞进很窄的姓名行，空间不够时整体缩放，
    // 绝不让 Row 溢出（大字模式下这几乎必然发生）。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: 3),
            Text(
              status.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 「临时调价」角标：这一笔用了与档案不同的单价。
///
/// 紫色是刻意选的：加班是暖橙、补录是红、结算是绿/蓝/橙，
/// 四类标签同屏出现时不能撞色，否则车间里一眼扫过去分不清哪个是哪个。
///
/// **只表示单价偏离了档案**，不代表档案被改过——
/// 计数页改价只写这一笔的单价快照，档案永远只在「设置 → 玩具工序」里改。
class TempPriceBadge extends StatelessWidget {
  const TempPriceBadge({super.key, this.compact = false, this.detail});

  final bool compact;

  /// 可选补充说明，如 `档案 0.20 → 本次 0.25`。
  final String? detail;

  static const Color color = Color(0xFF6A4C93);

  @override
  Widget build(BuildContext context) {
    final text = detail == null ? '临时调价' : '临时调价 $detail';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.price_change_outlined,
              size: compact ? 11 : 13,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
