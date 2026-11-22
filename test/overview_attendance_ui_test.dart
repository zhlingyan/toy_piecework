import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/ui/overview/overview_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// v1.8 概览页回归：出勤/总人数展示、名单面板、快捷按钮不折行。
void main() {
  late Fixture f;
  late AppServices services;

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
  });

  tearDown(() async {
    await f.dispose();
  });

  /// 页面在 didChangeDependencies 里跑真实 sqflite IO（而且是多次串行查询），
  /// 假时钟的 pumpAndSettle 会和它互相卡住。
  /// 与项目里其它弹层 UI 测试一致：推帧 + 真实异步交替推进，最后补一帧。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 60));
  }

  Future<void> pumpOverview(WidgetTester tester, {double scale = 1.0}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const OverviewPage(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('出勤人数显示 出勤/总人数，点击弹出全员名单', (tester) async {
    // 真实 sqflite IO 必须在 runAsync 里跑：testWidgets 的假时钟不会推进
    // 这些查询的 microtask，直接在测试体 await 会永久挂起。
    await tester.runAsync(() async {
      final a = await f.addWorker('甲');
      final b = await f.addWorker('乙');
      await f.addWorker('丙');
      final toy = await f.addToy('球', priceTenThousandth: 1000);
      final today = Dates.ymd(DateTime.now());
      await f.records.create(
        date: today,
        worker: a,
        toy: toy,
        quantity: 3,
      );
      await f.adjustments.create(
        date: today,
        worker: b,
        type: AdjustmentType.bonus,
        amountCents: 500,
        remark: '奖励',
      );
    });

    await pumpOverview(tester);
    expect(find.text('出勤人数'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.text('2/3'));
    await settle(tester);

    expect(find.textContaining('今日出勤'), findsOneWidget);
    // 名单里两名已出勤各一个「已出勤」徽标，一名未出勤一个「未出勤」徽标
    expect(find.text('已出勤'), findsNWidgets(2));
    expect(find.text('未出勤'), findsOneWidget);
    expect(find.textContaining('共 3 人'), findsOneWidget);
    expect(find.text('还没有工人档案'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('无工人档案时 0/0 安全展示，名单面板给空态', (tester) async {
    await pumpOverview(tester);
    expect(find.text('0/0'), findsOneWidget);

    await tester.tap(find.text('0/0'));
    await settle(tester);

    expect(find.text('还没有工人档案'), findsOneWidget);
    expect(find.text('已出勤'), findsNothing);
    expect(find.text('未出勤'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('马上计数按钮：图标与文字同一行，放大字号也不折行', (tester) async {
    await pumpOverview(tester, scale: 2.0);

    final labelFinder = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == '马上计数',
    );
    expect(labelFinder, findsOneWidget);
    final label = tester.widget<Text>(labelFinder);
    expect(label.maxLines, 1, reason: '禁止「马上计 / 数」折行');
    expect(label.softWrap, false);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('去结算'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '大字号下不得溢出');

    // 点击不崩溃（未包 SelectionScope 时跳转为空操作）
    await tester.tap(find.text('马上计数'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
