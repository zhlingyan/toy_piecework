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
          // 字号 = 系统缩放 × 用户在设置里选的档位（标准 1.0 / 大 1.3 / 超大 1.6）。
          //
          // 上限放到 2.4：系统调到最大又选了「超大」时仍会被夹住，
          // 否则个别页面（日期选择器、时间选择器）会挤成一团。
          // 各页面已按 1.6 倍做过溢出测试，见 test/font_scale_test.dart。
          return AnimatedBuilder(
            animation: widget.services.settings,
            builder: (context, _) {
              final systemScaler = MediaQuery.textScalerOf(context);
              final systemFactor = systemScaler.scale(14) / 14;
              final userScale = widget.services.settings.fontScale;
              final factor = (systemFactor * userScale).clamp(0.8, 2.4);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(factor),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
        home: AutoBackupGate(child: HomeShell(selection: widget.selection)),
        ),
      ),
    );
  }
}
