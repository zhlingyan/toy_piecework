/// 月度锁账标记。
class LockedMonth {
  const LockedMonth({
    required this.month,
    required this.isLocked,
    required this.lockedAt,
    required this.unlockedAt,
  });

  factory LockedMonth.fromMap(Map<String, Object?> map) {
    return LockedMonth(
      month: map['month']! as String,
      isLocked: (map['is_locked'] as int? ?? 0) == 1,
      lockedAt: map['locked_at'] as int?,
      unlockedAt: map['unlocked_at'] as int?,
    );
  }

  /// `YYYY-MM`。
  final String month;
  final bool isLocked;
  final int? lockedAt;
  final int? unlockedAt;

  Map<String, Object?> toMap() => {
        'month': month,
        'is_locked': isLocked ? 1 : 0,
        'locked_at': lockedAt,
        'unlocked_at': unlockedAt,
      };
}
