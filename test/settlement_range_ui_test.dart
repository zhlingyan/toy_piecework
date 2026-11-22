import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/settlement/settlement_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 结算页区间入口：点开是完整列表，选中立刻生效，自定义仍然可用。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;
  final now = DateTime(2026, 11, 22, 10, 0);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    zhang = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    // 上个月（10 月）与这个月（11 月）各记一笔
    await f.records.create(
      date: '2026-10-15',
      worker: zhang,
      toy: toy,
      quantity: 100,
    );
    await f.records.create(
      date: '2026-11-05',
      worker: zhang,
      toy: toy,
      quantity: 200,
    );
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
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
          home: SettlementPage(selection: SelectionState()),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('区间入口点开是分组的完整列表，每项都带起止日期', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    // 默认本月
    expect(find.text('这个月'), findsOneWidget);
    expect(find.textContaining('2026-11-01 ~ 2026-11-30'), findsOneWidget);

    await tester.tap(find.text('切换区间'));
    await settle(tester);

    // 五个周期分组
    for (final title in ['周', '月', '季度', '半年', '年']) {
      expect(find.text(title), findsWidgets, reason: '缺少 $title 分组');
    }
    // 十个快捷项
    for (final label in [
      '本周',
      '上周',
      '这个月',
      '上个月',
      '这个季度',
      '上个季度',
      '这半年',
      '上半年',
      '这一年',
      '上一年',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少 $label');
    }
    // 选中前就能看到起止日期
    expect(find.textContaining('2026-10-01 ~ 2026-10-31'), findsWidgets);
    expect(find.textContaining('2026-07-01 ~ 2026-12-31'), findsWidgets);
    // 自定义入口仍在
    expect(find.text('自定义区间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中「上个月」立刻切换区间并刷新统计', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    // 11 月：200 件 × 0.20 = 40.00
    expect(find.text('40.00'), findsWidgets);

    await tester.tap(find.text('切换区间'));
    await settle(tester);
    await tester.tap(find.text('上个月'));
    await settle(tester);

    expect(find.text('上个月'), findsOneWidget);
    expect(find.textContaining('2026-10-01 ~ 2026-10-31'), findsOneWidget);
    // 10 月：100 件 × 0.20 = 20.00
    expect(find.text('20.00'), findsWidgets);
    expect(find.text('40.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在历史区间里补录调整项，默认日期落在该区间而不是今天', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    await tester.tap(find.text('切换区间'));
    await settle(tester);
    await tester.tap(find.text('上个月'));
    await settle(tester);

    // 点右上角「记一笔补贴 / 扣款」
    await tester.tap(find.byIcon(Icons.add_card_outlined));
    await settle(tester);

    // 默认日期是区间最后一天 10-31，不是今天 11-22
    expect(find.text('2026-10-31'), findsOneWidget);
    expect(find.text('2026-11-22'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
