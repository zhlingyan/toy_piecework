import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/ui/settlement/worker_detail_sheet.dart';
import 'package:toy_piecework/ui/settlement/worker_records_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 逐条明细页 + 结算弹层交互。
///
/// 页面里都是真实数据库查询，必须用 runAsync 推进真实异步，
/// 否则 pumpAndSettle 会卡在假时钟上。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;
  const range = DateRange(start: '2026-06-01', end: '2026-07-31');

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());

    zhang = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-06-10',
      worker: zhang,
      toy: toy,
      quantity: 500,
    );
    await f.adjustments.create(
      date: '2026-06-10',
      worker: zhang,
      type: AdjustmentType.bonus,
      amountCents: 2000,
      remark: '全勤奖',
    );
    await f.records.create(
      date: '2026-07-05',
      worker: zhang,
      toy: toy,
      quantity: 100,
    );
  });

  tearDown(() async {
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 360×780 的手机尺寸，用来验证大字号不会把行挤爆。
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
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

  testWidgets('详细明细：逐条显示日期、工序、金额与结算状态', (tester) async {
    useTallView(tester);
    await tester.runAsync(
      () => f.settlementMarks.markSettled(
        workerId: zhang.id,
        months: ['2026-06'],
        settled: true,
      ),
    );

    await tester.pumpWidget(
      wrap(
        WorkerRecordsPage(
          workerId: zhang.id,
          workerName: zhang.name,
          workerCode: zhang.code,
          range: range,
        ),
      ),
    );
    await settle(tester);

    // 日期分组（带星期）
    expect(find.textContaining('2026-06-10'), findsWidgets);
    expect(find.textContaining('2026-07-05'), findsWidgets);
    // 工序与调整项
    expect(find.text('小熊'), findsWidgets);
    expect(find.text('全勤奖'), findsOneWidget);
    // 两个区间状态都出现
    expect(find.text('已结算'), findsWidgets);
    expect(find.text('未结算'), findsWidgets);
    // 合计 120.00 + 20.00 = 140.00
    expect(find.text('140.00'), findsWidgets);

    // 筛选：只看未结算，6 月的两条应消失
    expect(find.text('全部 3'), findsOneWidget);
    await tester.tap(find.text('未结算 1'));
    await settle(tester);
    expect(find.textContaining('2026-06-10'), findsNothing);
    expect(find.textContaining('2026-07-05'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结算弹层：详细明细可打开，标记已结算后状态同步', (tester) async {
    useTallView(tester);
    final result = await tester.runAsync(
      () => f.settlements.settle(range),
    );
    final settlement = result!.workers.single;
    expect(settlement.settlementStatus.label, '未结算');

    late BuildContext pageContext;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    await settle(tester);

    showWorkerDetailSheet(
      context: pageContext,
      services: services,
      worker: settlement,
      range: range,
    );
    await settle(tester);

    expect(find.text('详细明细'), findsOneWidget);
    expect(find.text('标记本期已结算'), findsOneWidget);

    await tester.tap(find.text('详细明细'));
    await settle(tester);
    expect(find.text('张三 · 明细'), findsOneWidget);

    // 返回弹层，标记已结算
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.text('标记本期已结算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('只做状态标记'), findsOneWidget);

    await tester.tap(find.text('标记已结算'));
    await settle(tester);
    expect(
      await tester.runAsync(
        () => f.settlementMarks.isSettled(zhang.id, '2026-06'),
      ),
      isTrue,
    );
    expect(
      await tester.runAsync(
        () => f.settlementMarks.isSettled(zhang.id, '2026-07'),
      ),
      isTrue,
    );
    expect(find.text('已结算'), findsWidgets);

    // 关闭弹层，避免测试结束时还有未完成的页面
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
  });

  testWidgets('超大字号下明细页与结算弹层都不溢出', (tester) async {
    usePhoneSize(tester);

    await tester.pumpWidget(
      wrap(
        WorkerRecordsPage(
          workerId: zhang.id,
          workerName: '张三（临时工）',
          workerCode: zhang.code,
          range: range,
        ),
        textScale: 1.6,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '明细页在超大字号下溢出了');
    expect(find.text('未结算'), findsWidgets);

    // 往下滚，覆盖日期分组与底部说明
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -240));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '明细页滚动中溢出了');
    }

    // 结算弹层同样过一遍
    final result = await tester.runAsync(() => f.settlements.settle(range));
    expect(result, isNotNull);
    late BuildContext pageContext;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
        textScale: 1.6,
      ),
    );
    await settle(tester);

    showWorkerDetailSheet(
      context: pageContext,
      services: services,
      worker: result!.workers.single,
      range: range,
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '结算弹层在超大字号下溢出了');
    expect(find.text('详细明细'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
