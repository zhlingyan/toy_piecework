import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/count/count_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 计数页：进入即今天、补录提示、日历上的假期角标。
void main() {
  late Fixture f;
  late AppServices services;
  late SelectionState selection;
  final now = DateTime(2026, 11, 22, 10, 0);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    await f.addWorker('张三');
    await f.addToy('小熊', priceTenThousandth: 2000);
    selection = SelectionState();
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 60));
  }

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: CountPage(selection: selection),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('上次留在 11 号，进入「马上计数」会回到今天', (tester) async {
    useTallView(tester);
    selection.date = '2026-11-11';
    await pumpPage(tester);

    // 页面自己先把旧日期显示出来（补录态）
    expect(find.textContaining('2026-11-11'), findsWidgets);
    expect(find.textContaining('正在补录'), findsOneWidget);

    // 从概览点「马上计数」等价于切到计数页签
    selection.tabIndex = SelectionState.countTabIndex;
    await settle(tester);

    expect(find.textContaining('2026-11-22（今天）'), findsOneWidget);
    expect(find.textContaining('正在补录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('补录态给出提示，并可以一键回到今天', (tester) async {
    useTallView(tester);
    selection.tabIndex = SelectionState.countTabIndex;
    await pumpPage(tester);

    selection.date = '2026-10-01';
    await settle(tester);

    expect(
      find.textContaining('正在补录 2026-10-01（今天 2026-11-22）'),
      findsOneWidget,
    );
    // 国庆节角标
    expect(find.textContaining('国庆节'), findsWidgets);

    await tester.tap(find.text('回今天'));
    await settle(tester);
    expect(find.textContaining('2026-11-22（今天）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改日期弹出日历，法定假与调休补班都有角标', (tester) async {
    useTallView(tester);
    selection.tabIndex = SelectionState.countTabIndex;
    selection.date = '2026-10-01';
    await pumpPage(tester);

    await tester.tap(find.text('改日期'));
    await settle(tester);

    // 2026 年 10 月：1–7 日放假、10 日补班
    expect(find.text('休'), findsWidgets);
    expect(find.text('班'), findsWidgets);
    expect(find.textContaining('国庆节'), findsWidgets);
    expect(find.textContaining('调休上班'), findsWidgets);
    expect(find.text('2026 年 10 月'), findsOneWidget);

    // 点「今天」直接回到今天并关闭
    await tester.tap(find.text('今天'));
    await settle(tester);
    expect(find.textContaining('2026-11-22（今天）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
