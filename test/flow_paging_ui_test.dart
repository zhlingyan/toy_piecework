import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/data/models/toy.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/count/count_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 计数页流水：按工人查找（姓名 / 工号）+ 每页 10/20/50 分页联动。
void main() {
  late Fixture f;
  late AppServices services;
  late SelectionState selection;
  late Worker zhang;
  late Worker li;
  late Toy bear;
  final now = DateTime(2026, 11, 22, 16, 32, 41);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    zhang = await f.addWorker('张三'); // W001
    li = await f.addWorker('李四'); // W002
    bear = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20 元

    // 12 笔：张三 8 笔（R01–R08），李四 4 笔（R09–R12）。
    // 用递增的分钟数保证排序稳定（测试时钟是冻结的，created_at 全相同）。
    for (var i = 1; i <= 12; i++) {
      await f.records.create(
        date: '2026-11-22',
        worker: i <= 8 ? zhang : li,
        toy: bear,
        quantity: 10,
        remark: 'R${i.toString().padLeft(2, '0')}',
        minuteOfDay: i * 10,
      );
    }

    selection = SelectionState();
    selection.tabIndex = SelectionState.countTabIndex;
    selection.date = '2026-11-22';
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

  void useTallView(WidgetTester tester, {double height = 6000}) {
    tester.view.physicalSize = Size(1080, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget wrap(Widget page, {double textScale = 1.0}) {
    return AppScope(
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
        home: page,
      ),
    );
  }

  Finder flowSearch() => find.byKey(const ValueKey('flow-search'));

  testWidgets('每页条数默认 20，切到 10 后翻页，切 50 回到一页', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(CountPage(selection: selection)));
    await settle(tester);

    // 12 笔 < 20 条/页：一页装得下，但已经超过最小档位，所以分页条会出现
    expect(find.text('第 1/1 页'), findsOneWidget);
    expect(find.textContaining('备注：R01'), findsOneWidget);
    expect(find.textContaining('备注：R12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flow-page-size-10')));
    await settle(tester);
    expect(find.text('第 1/2 页'), findsOneWidget);
    // 按时间倒序：最新的 R12 在第一页，最早的 R01/R02 在第二页
    expect(find.textContaining('备注：R12'), findsOneWidget);
    expect(find.textContaining('备注：R02'), findsNothing);
    expect(find.textContaining('备注：R01'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('flow-page-next')));
    await settle(tester);
    expect(find.text('第 2/2 页'), findsOneWidget);
    expect(find.textContaining('备注：R02'), findsOneWidget);
    expect(find.textContaining('备注：R01'), findsOneWidget);
    expect(find.textContaining('备注：R12'), findsNothing);

    // 切回大档位必须回到第一页，否则会停在越界的空白页
    await tester.tap(find.byKey(const ValueKey('flow-page-size-50')));
    await settle(tester);
    expect(find.text('第 1/1 页'), findsOneWidget);
    expect(find.textContaining('备注：R01'), findsOneWidget);
    expect(find.textContaining('备注：R12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按姓名 / 工号查找流水，无匹配有空状态并可一键清空', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(CountPage(selection: selection)));
    await settle(tester);

    await tester.enterText(flowSearch(), '李四');
    await settle(tester);
    expect(find.textContaining('匹配 4/12 笔'), findsOneWidget);
    expect(find.textContaining('备注：R09'), findsOneWidget);
    expect(find.textContaining('备注：R01'), findsNothing);

    // 工号也能查：流水只存姓名快照，工号是从档案补的
    await tester.enterText(flowSearch(), 'W001');
    await settle(tester);
    expect(find.textContaining('匹配 8/12 笔'), findsOneWidget);
    expect(find.textContaining('备注：R01'), findsOneWidget);
    expect(find.textContaining('备注：R09'), findsNothing);

    // 姓名的拼音首字母也能命中
    await tester.enterText(flowSearch(), 'ls');
    await settle(tester);
    expect(find.textContaining('匹配 4/12 笔'), findsOneWidget);

    await tester.enterText(flowSearch(), '王五');
    await settle(tester);
    expect(find.text('没有匹配的流水'), findsOneWidget);
    expect(find.textContaining('匹配 0/12 笔'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清空查找'));
    await settle(tester);
    expect(find.textContaining('备注：R01'), findsOneWidget);
    expect(find.textContaining('备注：R12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查找与分页联动：筛到 4 条时页码回到第 1 页', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(CountPage(selection: selection)));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('flow-page-size-10')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('flow-page-next')));
    await settle(tester);
    expect(find.text('第 2/2 页'), findsOneWidget);

    // 换查找词后结果只剩 4 条：必须回到第 1 页，否则会看到空白
    await tester.enterText(flowSearch(), '李四');
    await settle(tester);
    expect(find.text('第 1/1 页'), findsOneWidget);
    expect(find.textContaining('备注：R09'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('超大字号下查找条与分页条不溢出', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(
      wrap(CountPage(selection: selection), textScale: 1.6),
    );
    await settle(tester);

    expect(find.text('第 1/1 页'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flow-page-size-10')));
    await settle(tester);
    expect(find.text('第 1/2 页'), findsOneWidget);

    await tester.enterText(flowSearch(), '张三');
    await settle(tester);
    expect(find.textContaining('匹配 8/12 笔'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
