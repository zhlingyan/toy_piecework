import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/toy.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/count/count_page.dart';
import 'package:toy_piecework/ui/settlement/worker_records_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 计数页的临时调价、录入时结算、以及流水行的防堆叠排版。
void main() {
  late Fixture f;
  late AppServices services;
  late SelectionState selection;
  late Worker zhang;
  late Toy bear;
  final now = DateTime(2026, 11, 22, 16, 32, 41);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    zhang = await f.addWorker('张三');
    bear = await f.addToy('小熊', priceTenThousandth: 2000); // 0.20 元
    selection = SelectionState();
    selection.tabIndex = SelectionState.countTabIndex;
    selection.workerId = zhang.id;
    selection.toyId = bear.id;
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

  void useTallView(WidgetTester tester, {double height = 2600}) {
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

  testWidgets('临时调价回填纯数字，保存后档案单价不动，行上带「临时调价」', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(CountPage(selection: selection)));
    await settle(tester);

    await tester.tap(find.text('临时调价'));
    await settle(tester);

    // 这是关键回归点：早先回填的是「0.20 元」，解析必失败
    final priceField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(priceField.controller!.text, '0.20');
    expect(find.textContaining('临时调价只对这一笔生效'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '10');
    await tester.enterText(find.byType(TextField).at(1), '0.25');
    await settle(tester);

    await tester.tap(find.text('保存这一笔'));
    await settle(tester);

    final records = await tester.runAsync(
      () => f.records.listByDate('2026-11-22'),
    );
    expect(records!.single.unitPriceSnapshot, 2500);
    expect(records.single.subtotalCents, 250);

    // 档案必须原封不动——这是"防串库"的底线
    final archived = await tester.runAsync(() => f.toys.findById(bear.id));
    expect(archived!.unitPriceTenThousandth, 2000);

    // 流水行上自动出现「临时调价」角标
    expect(find.text('临时调价'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('录入时打开「这一笔已结算」，保存即按已结算入账', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(CountPage(selection: selection)));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('count-settle-switch')));
    await settle(tester);
    expect(find.text('这一笔：已结算'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '100');
    await settle(tester);
    await tester.tap(find.text('保存这一笔'));
    await settle(tester);

    final records = await tester.runAsync(
      () => f.records.listByDate('2026-11-22'),
    );
    expect(records!.single.settledAt, isNotNull);

    final worker = (await tester.runAsync(
      () => f.settlements.settle(DateRange.of('2026-11-01', '2026-11-30')),
    ))!
        .workers
        .single;
    expect(worker.settlementStatus.label, '已结算');
    expect(worker.settledCents, 2000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('明细页可以逐笔结算与取消', (tester) async {
    final toy = bear;
    await tester.runAsync(
      () => f.records.create(
        date: '2026-11-01',
        worker: zhang,
        toy: toy,
        quantity: 100, // 20.00
      ),
    );
    await tester.runAsync(
      () => f.records.create(
        date: '2026-11-02',
        worker: zhang,
        toy: toy,
        quantity: 50, // 10.00
      ),
    );

    useTallView(tester);
    await tester.pumpWidget(
      wrap(
        WorkerRecordsPage(
          workerId: zhang.id,
          workerName: zhang.name,
          workerCode: zhang.code,
          range: const DateRange(start: '2026-11-01', end: '2026-11-30'),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('结算'), findsNWidgets(2));
    expect(find.text('已结算 0 笔'), findsNothing); // 数字在状态卡里

    await tester.tap(find.text('结算').first);
    await settle(tester);

    // 结完立刻变成「取消」，汇总跟着动
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('已结算'), findsWidgets);

    final worker = (await tester.runAsync(
      () => f.settlements.settle(DateRange.of('2026-11-01', '2026-11-30')),
    ))!
        .workers
        .single;
    expect(worker.settledCount, 1);
    expect(worker.recordCount, 2);
    expect(worker.settlementStatus.label, '部分已结');
    expect(worker.settledCents + worker.unsettledCents, worker.netCents);

    // 再取消这一笔：不需要二次确认（它是单笔标记，不是整月展开）
    await tester.tap(find.text('取消'));
    await settle(tester);
    final back = (await tester.runAsync(
      () => f.settlements.settle(DateRange.of('2026-11-01', '2026-11-30')),
    ))!
        .workers
        .single;
    expect(back.settledCount, 0);
    expect(back.settlementStatus.label, '未结算');
    expect(tester.takeException(), isNull);
  });

  testWidgets('超大字号下流水行两行布局不堆叠、不溢出', (tester) async {
    // 一笔集齐：加班 + 临时调价 + 补录 + 长备注
    await tester.runAsync(
      () => f.records.create(
        date: '2026-11-11',
        worker: zhang,
        toy: bear,
        quantity: 1200,
        unitPriceTenThousandth: 2500,
        overtime: true,
        overtimePriceTenThousandth: 3000,
        overtimeMultiplier: 1500,
        remark: '蓝色款返工后重新计数，备注故意写很长很长很长',
      ),
    );

    // 页面只列"所选日期"的流水，补录那笔要选中 11 号才看得见
    selection.date = '2026-11-11';
    // 视口给足：ListView 只建可见区域，太矮会看不到底部的流水行
    useTallView(tester, height: 6000);
    await tester.pumpWidget(
      wrap(CountPage(selection: selection), textScale: 1.6),
    );
    await settle(tester);

    expect(find.text('临时调价'), findsWidgets);
    expect(find.textContaining('加班 ×1.5'), findsWidgets);
    expect(find.textContaining('补录 11 天'), findsWidgets);
    expect(find.textContaining('备注：蓝色款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
