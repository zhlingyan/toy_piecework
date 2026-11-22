import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'services/app_services.dart';
import 'services/app_settings.dart';
import 'state/selection_state.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final db = await AppDatabase.open();
    final settings = await AppSettings.load();
    final services = AppServices(db: db, settings: settings);
    runApp(
      ToyPieceworkApp(
        services: services,
        selection: SelectionState(),
      ),
    );
  } catch (error) {
    runApp(_StartupFailureApp(message: '$error'));
  }
}

/// 启动失败兜底页：数据库打不开时给出可读提示，而不是白屏。
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 54, color: AppTheme.danger),
                const SizedBox(height: 16),
                const Text(
                  '账本打不开了',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  '请重启应用。如果一直这样，先把手机里的备份文件留好，再联系技术支持。\n\n$message',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
