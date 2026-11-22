import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_scope.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/count/count_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 调整项「从点按钮到进结算」的整条链路。
///
/// 这一条最容易出问题的不是算法，而是**入口到落库之间断掉**：
/// 弹窗能打开、按钮能点，但存完列表里看不到，用户就以为没生效。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;
  late SelectionState selection;

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    services = AppServices(db: f.db, settings: settings);

    zhang = await f.addWorker('张三');
    selection = SelectionState()..workerId = zhang.id;
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

  /// 视口刻意拉高：计数页是一个懒加载 ListView，
  /// 屏幕外的分区根本不会被构建，`find.text` 自然找不到。
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpCountPage(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: SelectionScope(
          selection: selection,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: CountPage(selection: selection),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// 弹窗里的输入框（按树顺序：金额在备注之前）。
  Finder sheetField(int index) => find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      )
      .at(index);

  testWidgets('点「扣款」记一笔，列表里看得到，结算里算对了', (tester) async {
    await pumpCountPage(tester);

    // 四个入口都在页面上（不是藏在菜单里）
    expect(find.text('扣款'), findsWidgets, reason: '四个入口要直接可见');
    expect(find.text('补贴'), findsWidgets);
    expect(find.text('计时'), findsWidgets);
    expect(find.text('预支'), findsWidgets);

    await tester.tap(find.text('扣款'));
    await settle(tester);
    expect(find.text('录入调整项'), findsOneWidget, reason: '弹窗要能打开');

    await tester.enterText(sheetField(0), '50');
    await tester.enterText(sheetField(1), '次品赔偿');
    await settle(tester);

    await tester.tap(find.text('保存调整项'));
    await settle(tester);

    // 1) 落库：类型是扣款、金额 50 元
    // 测试体里读真库必须包在 runAsync 里，否则会卡在假时钟上
    final saved = await tester.runAsync(
      () => f.adjustments.listRange(
        DateRange(start: selection.date, end: selection.date),
      ),
    );
    expect(saved!.length, 1);
    expect(saved.single.type, AdjustmentType.deduction);
    expect(saved.single.amountCents, 5000);

    // 2) 当天列表里能看到这一笔（不再是「存了没反应」）
    expect(find.text('次品赔偿'), findsWidgets);
    expect(find.text('-50.00 元'), findsWidgets);
    expect(find.text('合计 -50.00'), findsOneWidget);

    // 3) 结算读到的是减项
    final result = await tester.runAsync(
      () => f.settlements.settle(
        DateRange(start: selection.date, end: selection.date),
      ),
    );
    expect(result!.deductionTotal, 5000);
    expect(result.workers.single.netCents, -5000);
  });

  testWidgets('计时按工时×时薪算，金额自动算出来', (tester) async {
    await pumpCountPage(tester);

    await tester.tap(find.text('计时'));
    await settle(tester);

    expect(find.text('按工时 × 时薪'), findsOneWidget);

    // 工时分、时薪分两个输入框
    await tester.enterText(sheetField(0), '3.5');
    await tester.enterText(sheetField(1), '25');
    await tester.enterText(sheetField(2), '打包');
    await settle(tester);

    // 3.5 × 25 = 87.50，弹窗里就要显示出来
    expect(find.text('+87.50'), findsOneWidget);

    await tester.tap(find.text('保存调整项'));
    await settle(tester);

    final saved = await tester.runAsync(
      () => f.adjustments.listRange(
        DateRange(start: selection.date, end: selection.date),
      ),
    );
    expect(saved!.single.workMinutes, 210);
    expect(saved.single.hourlyRateCents, 2500);
    expect(saved.single.amountCents, 8750);
    expect(find.text('3.5 小时 × 25.00 元/时 · 打包'), findsWidgets);
  });

  testWidgets('工时填了但时薪没填，保存被拦下', (tester) async {
    await pumpCountPage(tester);

    await tester.tap(find.text('计时'));
    await settle(tester);

    await tester.enterText(sheetField(0), '3.5');
    await tester.enterText(sheetField(2), '打包');
    await settle(tester);

    await tester.tap(find.text('保存调整项'));
    await settle(tester);

    final saved = await tester.runAsync(
      () => f.adjustments.listRange(
        DateRange(start: selection.date, end: selection.date),
      ),
    );
    expect(saved, isEmpty, reason: '算不出金额就不能存');
    expect(find.text('录入调整项'), findsOneWidget, reason: '弹窗应留在原地');
  });
}
