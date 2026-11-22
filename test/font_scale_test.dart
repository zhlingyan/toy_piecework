import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/app.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_scope.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/archives/worker_profile_page.dart';
import 'package:toy_piecework/ui/reports/annual_page.dart';
import 'package:toy_piecework/ui/settings/settings_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 超大字号下的排版回归测试。
///
/// 把字号拉到 1.6 倍（设置里的「超大」），在 360×780 的手机尺寸下
/// 逐个页面渲染。任何 `RenderFlex overflowed` 都会让用例失败——
/// 比人工盯屏幕找错位可靠得多。
///
/// 失败时的典型修法：把 `Row` 里的文字包进 `Expanded`/`Flexible`，
/// 或者把并排的数字块换成 `Wrap`。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({
      'font_scale': 1.6, // 超大档
      'overtime_auto_detect': true,
      'work_end_minute': 18 * 60,
    });
    final settings = await AppSettings.load();
    services = AppServices(db: f.db, settings: settings);

    zhang = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: Dates.ymd(DateTime.now()),
      worker: zhang,
      toy: toy,
      quantity: 500,
      minuteOfDay: 19 * 60 + 30,
      overtime: true,
      overtimePriceTenThousandth: 3000,
      overtimeMultiplier: 1500,
    );
    await f.adjustments.create(
      date: Dates.ymd(DateTime.now()),
      worker: zhang,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤奖',
    );
  });

  tearDown(() async {
    await f.dispose();
  });

  /// 数据库是真 IO，必须用 runAsync 推进，否则会卡在假时钟里。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 60));
  }

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 单独挂一个页面（带齐 AppScope / SelectionScope / 主题）。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    final selection = SelectionState();
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: SelectionScope(
          selection: selection,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: page,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('超大字号下四个页签都不溢出', (tester) async {
    usePhoneSize(tester);

    final selection = SelectionState();
    await tester.pumpWidget(
      ToyPieceworkApp(services: services, selection: selection),
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '概览页在超大字号下溢出了');

    selection.tabIndex = 1;
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '计数页在超大字号下溢出了');

    selection.tabIndex = 2;
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '结算页在超大字号下溢出了');

    selection.tabIndex = 3;
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '设置页在超大字号下溢出了');

    // 滚到底，覆盖首屏之下的所有分区
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -260));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '设置页滚动中溢出了（第 $i 屏）');
    }
    expect(find.text('关于'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('超大字号下设置页各分区都能渲染', (tester) async {
    usePhoneSize(tester);
    await pumpPage(tester, const SettingsPage());

    expect(find.text('显示与字号'), findsOneWidget);
    expect(find.text('加班'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('超大字号下年度报表与员工档案不溢出', (tester) async {
    usePhoneSize(tester);

    await pumpPage(tester, const AnnualPage());
    expect(tester.takeException(), isNull, reason: '年度报表页在超大字号下溢出了');

    await pumpPage(tester, WorkerProfilePage(worker: zhang));
    expect(tester.takeException(), isNull, reason: '员工档案页在超大字号下溢出了');

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('字号档位切换会立刻改变缩放倍数', (tester) async {
    usePhoneSize(tester);
    // 必须走真实 App 入口：字号缩放是在 MaterialApp.builder 里施加的
    final selection = SelectionState()..tabIndex = 3;
    await tester.pumpWidget(
      ToyPieceworkApp(services: services, selection: selection),
    );
    await settle(tester);

    double currentScale() {
      final context = tester.element(find.text('显示与字号'));
      return MediaQuery.textScalerOf(context).scale(10) / 10;
    }

    expect(currentScale(), closeTo(1.6, 0.001));

    await tester.runAsync(() => services.settings.setFontScale(1.0));
    await settle(tester);
    expect(currentScale(), closeTo(1.0, 0.001), reason: '换档后应立即生效');

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
