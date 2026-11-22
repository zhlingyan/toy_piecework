import 'package:material_ui/material_ui.dart';

import 'services/app_services.dart';
import 'state/selection_scope.dart';
import 'state/selection_state.dart';
import 'ui/shell/auto_backup_gate.dart';
import 'ui/shell/home_shell.dart';
import 'ui/theme.dart';

/// 应用根节点：注入服务、主题、中文本地化（日期选择器等系统控件均为中文）。
class ToyPieceworkApp extends StatefulWidget {
  const ToyPieceworkApp({
    super.key,
    required this.services,
    required this.selection,
  });

  final AppServices services;
  final SelectionState selection;

  @override
  State<ToyPieceworkApp> createState() => _ToyPieceworkAppState();
}

class _ToyPieceworkAppState extends State<ToyPieceworkApp> {
  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      refresh: widget.services.refresh,
      child: SelectionScope(
        selection: widget.selection,
        child: MaterialApp(
        title: '玩具厂计件',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        // material_ui 自带 Material + Cupertino 全局本地化代理
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          // 长辈友好：在系统字号基础上再放大 14%，并锁定 1.0–1.3 的区间，
          // 避免把系统字号调到最大时文字溢出、按钮被挤掉。
          final systemScaler = MediaQuery.textScalerOf(context);
          final systemFactor = systemScaler.scale(14) / 14;
          final factor = (systemFactor * 1.14).clamp(1.0, 1.3);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(factor),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: AutoBackupGate(child: HomeShell(selection: widget.selection)),
        ),
      ),
    );
  }
}
