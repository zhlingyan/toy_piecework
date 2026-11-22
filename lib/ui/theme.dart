import 'package:material_ui/material_ui.dart';

/// 长辈友好主题：大字号、高对比、宽点击热区。
///
/// 车间环境光线杂、使用者年龄偏大，正文不低于 17sp，
/// 关键金额与保存按钮用更大的字号与更粗的字重。
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF14549B);
  static const Color danger = Color(0xFFC62828);
  static const Color success = Color(0xFF1B7F3B);
  static const Color background = Color(0xFFF2F4F7);
  static const Color surface = Colors.white;
  static const Color muted = Color(0xFF5B6472);

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      error: danger,
      surface: surface,
    );

    final base = ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      visualDensity: VisualDensity.comfortable,
    );

    // 只统一字体回退，不在这里放大字号。
    //
    // material_ui 的部分字号为 null，调用 apply(fontSizeFactor:) 会触发
    // TextStyle.apply 的断言（debug 直接崩、release 静默失效）。
    // 放大字号统一交给 app.dart 里的 textScaler 处理，一处生效、可控上下限。
    final textTheme = base.textTheme.apply(
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
      ],
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 58),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7DBE3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7DBE3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontSize: 17),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE6E9EF), thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 14),
        elevation: 8,
      ),
    );
  }
}
