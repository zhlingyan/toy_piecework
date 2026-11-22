import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/settlement/settlement_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 问题 16：单一按钮整合排序与已结/未结，三条件（状态 / 查找 / 排序）联动。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker a10; // 张三 · A10 · 20.00 · 已结
  late Worker a2; // 李四 · A2 · 10.00 · 未结
  late Worker leading002; // 王五 · 002 · 6.00 · 未结
  final nov = DateRange.of('2026-11-01', '2026-11-30');
  final now = DateTime(2026, 11, 22, 10, 0);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    // 工号刻意让「自然序」与「字典序」不同：002 < A2 < A10
    a10 = await f.addWorker('张三', code: 'A10');
    a2 = await f.addWorker('李四', code: 'A2');
    leading002 = await f.addWorker('王五', code: '002');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
        date: '2026-11-05', worker: a10, toy: toy, quantity: 100); // 20.00
    await f.records.create(
        date: '2026-11-06', worker: a2, toy: toy, quantity: 50); // 10.00
    await f.records.create(
        date: '2026-11-07', worker: leading002, toy: toy, quantity: 30); // 6.00
    await f.settlementEntries.markRange(
      workerId: a10.id,
      months: const ['2026-11'],
      range: nov,
      settled: true,
    );
  });

  tearDown(() async {
    AppClock.reset();
    await f.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 60));
  }

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpPage(WidgetTester tester, {double textScale = 1.0}) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: SettlementPage(selection: SelectionState()),
        ),
      ),
    );
    await settle(tester);
  }

  /// widget 树里「按工人结算」行的顺序（Column children 顺序 == 视觉顺序）。
  List<String> visibleIds(WidgetTester tester) => find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        if (key is! ValueKey) return false;
        final value = key.value.toString();
        // 排除查找框自身的 key：settlement-worker-search
        return value.startsWith('settlement-worker-') &&
            value != 'settlement-worker-search';
      })
      .evaluate()
      .map((element) => (element.widget.key! as ValueKey)
          .value
          .toString()
          .substring('settlement-worker-'.length))
      .toList();

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('worker-view-button')));
    await settle(tester);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('worker-view-done')));
    await settle(tester);
  }

  testWidgets('单一按钮面板：排序 / 方向 / 已结未结都在一处，筛选不改汇总',
      (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('worker-view-button')), findsOneWidget);
    expect(find.text('3/3 人'), findsOneWidget);
    // 升级前散落的状态 Chip 不再出现
    expect(find.text('全部 3'), findsNothing);

    await openSheet(tester);
    expect(find.byKey(const ValueKey('worker-view-sheet')), findsOneWidget);
    for (final key in const [
      'worker-sort-byName',
      'worker-sort-byCode',
      'worker-sort-byAmount',
      'worker-amount-desc',
      'worker-amount-asc',
      'worker-status-all',
      'worker-status-settled',
      'worker-status-unsettled',
      'worker-view-reset',
      'worker-view-done',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '$key 应在面板里');
    }

    // 选「未结」：背后列表立刻变成 2/3 人，但汇总仍按全员 36.00
    await tester.tap(find.byKey(const ValueKey('worker-status-unsettled')));
    await settle(tester);
    expect(find.text('2/3 人'), findsOneWidget);
    expect(find.text('36.00'), findsWidgets);
    expect(find.byKey(ValueKey('settlement-worker-${a10.id}')), findsNothing);

    await closeSheet(tester);
    expect(find.text('2/3 人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按工号自然序、按金额升降序：只改顺序不改人数', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('worker-sort-byCode')));
    await settle(tester);
    await closeSheet(tester);
    expect(visibleIds(tester), [leading002.id, a2.id, a10.id]);
    expect(find.text('3/3 人'), findsOneWidget);

    // 金额升序：6 → 10 → 20
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('worker-sort-byAmount')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('worker-amount-asc')));
    await settle(tester);
    await closeSheet(tester);
    expect(visibleIds(tester), [leading002.id, a2.id, a10.id]);

    // 金额降序：20 → 10 → 6
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('worker-amount-desc')));
    await settle(tester);
    await closeSheet(tester);
    expect(visibleIds(tester), [a10.id, a2.id, leading002.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('状态 + 查找 + 排序三者叠加不冲突，恢复默认可清空',
      (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('worker-status-unsettled')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('worker-sort-byCode')));
    await settle(tester);
    await closeSheet(tester);
    expect(find.text('2/3 人'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('settlement-worker-search')),
      '李四',
    );
    await settle(tester);
    expect(find.text('1/3 人'), findsOneWidget);
    expect(find.byKey(ValueKey('settlement-worker-${a2.id}')), findsOneWidget);
    expect(find.text('36.00'), findsWidgets, reason: '汇总不受查找影响');

    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await settle(tester);
    expect(find.text('2/3 人'), findsOneWidget);

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('worker-view-reset')));
    await settle(tester);
    await closeSheet(tester);
    expect(find.text('3/3 人'), findsOneWidget);
    expect(visibleIds(tester), [a10.id, a2.id, leading002.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.6 倍字号下面板与列表都不溢出', (tester) async {
    useTallView(tester);
    await pumpPage(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('worker-view-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('worker-status-settled')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
