import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_scope.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/archives/process_picker.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 工序选择器：点开就有常用项，新增的自定义项落库后还能再用。
void main() {
  late Fixture f;
  late AppServices services;

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    services = AppServices(db: f.db, settings: settings);
  });

  tearDown(() async {
    await f.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// 挂一个按钮，点它弹出选择器，把返回值显示出来。
  Future<void> pumpPickerHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: SelectionScope(
          selection: SelectionState(),
          child: MaterialApp(
            theme: AppTheme.build(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showProcessPicker(
                        context: context,
                        services: services,
                        current: Defaults.defaultProcess,
                      );
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          content: Text('选中：${picked ?? '无'}'),
                        ),
                      );
                    },
                    child: const Text('打开工序'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('点开就能看到常用工序，并标出当前选中项', (tester) async {
    await pumpPickerHost(tester);

    await tester.tap(find.text('打开工序'));
    await settle(tester);

    expect(find.text('选择工序'), findsOneWidget);
    expect(find.text('整件'), findsWidgets);
    expect(find.text('缝头'), findsOneWidget);
    expect(find.text('包装'), findsOneWidget);
    expect(find.text('新增工序'), findsOneWidget);

    // 选一项就返回这一项
    await tester.tap(find.text('缝头'));
    await settle(tester);
    expect(find.text('选中：缝头'), findsOneWidget);
  });

  testWidgets('新增自定义工序后立即选中，并沉淀到列表里', (tester) async {
    await pumpPickerHost(tester);

    await tester.tap(find.text('打开工序'));
    await settle(tester);

    await tester.tap(find.text('新增工序'));
    await settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '打眼',
    );
    await settle(tester);
    await tester.tap(find.text('保存'));
    await settle(tester);

    // 新增 → 直接选中返回
    expect(find.text('选中：打眼'), findsOneWidget);

    // 落库了：下次打开列表里就有，不用重新打
    final names = await tester.runAsync(() => services.processes.listNames());
    expect(names, contains('打眼'));

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
