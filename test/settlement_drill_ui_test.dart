import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/settlement/settlement_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 结算页：按工人查找、应付合计 / 月度锁账折叠、全员维度下钻与直接结算。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;
  late Worker li;
  late Worker wang;
  final nov = DateRange.of('2026-11-01', '2026-11-30');
  final now = DateTime(2026, 11, 22, 10, 0);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    zhang = await f.addWorker('张三'); // W001
    li = await f.addWorker('李四'); // W002
    wang = await f.addWorker('王五'); // W003
    final toy = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20 元

    await f.records.create(
        date: '2026-11-05', worker: zhang, toy: toy, quantity: 100); // 20.00
    await f.records.create(
        date: '2026-11-06', worker: li, toy: toy, quantity: 50); // 10.00
    await f.records.create(
        date: '2026-11-07', worker: wang, toy: toy, quantity: 30); // 6.00
    await f.adjustments.create(
      date: '2026-11-08',
      worker: li,
      type: AdjustmentType.deduction,
      amountCents: 300,
      remark: '次品扣款',
    );
    await f.adjustments.create(
      date: '2026-11-09',
      worker: wang,
      type: AdjustmentType.bonus,
      amountCents: 500,
      remark: '全勤奖',
    );
    // 张三整月已结，另外两人未结 → 汇总应是 已结 1 人 / 未结 2 人
    await f.settlementEntries.markRange(
      workerId: zhang.id,
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
    tester.view.physicalSize = const Size(1080, 3000);
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

  Future<double> netOf(String workerId) async {
    final result = await f.settlements.settle(nov, workerId: workerId);
    return result.workers.isEmpty ? 0 : result.workers.first.netCents / 100;
  }

  testWidgets('按工人结算支持姓名 / 工号查找，无匹配有空状态并可清空', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    expect(find.text('3/3 人'), findsOneWidget);

    final search = find.byKey(const ValueKey('settlement-worker-search'));
    await tester.enterText(search, '王五');
    await settle(tester);
    expect(find.text('1/3 人'), findsOneWidget);
    expect(find.byKey(ValueKey('settlement-worker-${wang.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('settlement-worker-${li.id}')), findsNothing);

    // 工号也能定位
    await tester.enterText(search, 'W002');
    await settle(tester);
    expect(find.byKey(ValueKey('settlement-worker-${li.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('settlement-worker-${wang.id}')), findsNothing);

    // 找不到人：空状态 + 清空入口，且不影响原有统计
    await tester.enterText(search, '赵六');
    await settle(tester);
    expect(find.text('没有匹配的工人'), findsOneWidget);
    expect(find.text('0/3 人'), findsOneWidget);
    // 汇总仍然按全员算，没有被查找词带偏
    expect(find.text('38.00'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, '清空查找'));
    await settle(tester);
    expect(find.text('3/3 人'), findsOneWidget);
    expect(find.byKey(ValueKey('settlement-worker-${wang.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应付合计可折叠：折叠态保留合计 / 已结算 / 未结算三块核心口径', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    // 展开态：明细项都在
    expect(find.text('计件'), findsOneWidget);
    expect(find.text('扣款'), findsOneWidget);
    expect(find.text('38.00'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('summary-collapse')));
    await settle(tester);

    // 明细项收起，但三个核心指标一个都不能少（总金额 38.00 = 已结 20 + 未结 18）
    expect(find.text('计件'), findsNothing);
    expect(find.text('扣款'), findsNothing);
    expect(find.text('38.00'), findsWidgets);
    expect(find.byKey(const ValueKey('summary-unsettled')), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-settled')), findsOneWidget);
    expect(find.text('20.00 元'), findsOneWidget); // 已结算
    expect(find.text('18.00 元'), findsOneWidget); // 未结算

    await tester.tap(find.byKey(const ValueKey('summary-collapse')));
    await settle(tester);
    expect(find.text('计件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月度锁账可折叠：折叠态只报已锁 / 未锁月份数', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    // 一个月区间默认展开，能直接看到月份圆片
    expect(find.text('2026-11 未锁'), findsOneWidget);
    expect(find.text('已锁 0 个月'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('locks-collapse')));
    await settle(tester);
    expect(find.text('2026-11 未锁'), findsNothing);
    expect(find.text('已锁 0 个月'), findsOneWidget);
    expect(find.text('未锁 1 个月'), findsOneWidget);

    // 展开后逐月锁定仍然可用
    await tester.tap(find.byKey(const ValueKey('locks-collapse')));
    await settle(tester);
    await tester.tap(find.text('2026-11 未锁'));
    await settle(tester);
    await tester.tap(find.text('确认锁账'));
    await settle(tester);
    expect(find.text('已锁 1 个月'), findsOneWidget);
    expect(find.text('2026-11 已锁'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「未结算」进全员名单，就地结清后汇总立刻变', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    expect(find.text('未结算 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('summary-unsettled')));
    await settle(tester);

    // 全员视角：两个还欠钱的人都在，已结清的不在
    expect(find.text('未结算 · 全员'), findsOneWidget);
    expect(find.byKey(ValueKey('drill-person-${li.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('drill-person-${wang.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('drill-person-${zhang.id}')), findsNothing);

    // 就地结清李四（净额 10 - 3 = 7.00）
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('drill-person-${li.id}')),
        matching: find.text('结清本期'),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('标记已结算'));
    await settle(tester);

    final marked = await tester.runAsync(() => netOf(li.id));
    expect(marked, 7.0);
    final liWorker = (await tester.runAsync(() => f.settlements.settle(nov)))!
        .workers
        .firstWhere((worker) => worker.workerId == li.id);
    expect(liWorker.isFullySettled, isTrue);

    // 汇总卡实时刷新（弹层还开着，后面的页面已重算）
    expect(find.text('未结算 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
    expect(find.text('未结算 1'), findsOneWidget);
    expect(find.text('已结算 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「扣款」按项目横切全员：能看到谁有扣款并逐笔结算', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('summary-metric-deduction')));
    await settle(tester);

    expect(find.text('扣款 · 全员'), findsOneWidget);
    expect(find.text('合计 -3.00 元 · 1 笔'), findsOneWidget);
    // 只有李四有扣款，张三王五不出现
    expect(find.byKey(ValueKey('drill-group-${li.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('drill-group-${wang.id}')), findsNothing);
    expect(find.text('-3.00'), findsOneWidget);

    // 展开这个工人，能看到逐笔与单笔结算入口
    await tester.tap(find.byKey(ValueKey('drill-group-${li.id}')));
    await settle(tester);
    expect(find.text('次品扣款'), findsOneWidget);

    final deduction = (await tester.runAsync(() => f.adjustments.listRange(nov)))!
        .firstWhere((item) => item.type == AdjustmentType.deduction);
    await tester.tap(find.byKey(ValueKey('drill-entry-settle-${deduction.id}')));
    await settle(tester);

    final result = await tester.runAsync(() => f.settlements.settle(nov));
    final liWorker =
        result!.workers.firstWhere((worker) => worker.workerId == li.id);
    expect(liWorker.settledCount, 1);
    expect(liWorker.settlementStatus.label, '部分已结');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「补贴」时若区间内没有这类账，给出提示而不是打开空弹层', (tester) async {
    useTallView(tester);
    await pumpPage(tester);

    // 先把王五的补贴删掉（软删除后该类型归零）
    final bonuses = await tester.runAsync(
      () => f.adjustments.listRange(nov),
    );
    final bonus = bonuses!.firstWhere((item) => item.type == AdjustmentType.bonus);
    await tester.runAsync(() => f.adjustments.softDelete(bonus.id));
    services.notifyDataChanged();
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('summary-metric-bonus')));
    await settle(tester);
    expect(find.text('这个区间没有补贴'), findsOneWidget);
    expect(find.text('补贴 · 全员'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('超大字号下折叠卡片与两个下钻弹层都不溢出', (tester) async {
    useTallView(tester);
    await pumpPage(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);

    // 折叠态
    await tester.tap(find.byKey(const ValueKey('summary-collapse')));
    await settle(tester);
    expect(find.byKey(const ValueKey('summary-unsettled')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 未结算下钻
    await tester.tap(find.byKey(const ValueKey('summary-unsettled')));
    await settle(tester);
    expect(find.text('未结算 · 全员'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    // 展开后按项目下钻，并展开一个工人看逐笔
    await tester.tap(find.byKey(const ValueKey('summary-collapse')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('summary-metric-deduction')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('drill-group-${li.id}')));
    await settle(tester);
    expect(find.text('次品扣款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
