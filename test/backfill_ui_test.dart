import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/ui/settlement/worker_records_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 明细页的「补录」识别、红色高亮与录入时间查看。
///
/// 时钟钉在 2026-11-22 16:32:41：11 号的活是**今天补录**的，
/// 页面必须把它放在 11 号那一组，同时标红 + 给出精确录入时间。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;
  final now = DateTime(2026, 11, 22, 16, 32, 41);

  setUp(() async {
    AppClock.override(() => now);
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    zhang = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-11-11',
      worker: zhang,
      toy: toy,
      quantity: 500,
    );
    await f.records.create(
      date: '2026-11-22',
      worker: zhang,
      toy: toy,
      quantity: 100,
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

  testWidgets('11 号补录的记录归在 11 号，并标「补录」', (tester) async {
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

    // 分组标题是 11 号与 22 号两组，而不是把两笔都堆到今天
    expect(find.textContaining('2026-11-11'), findsWidgets);
    expect(find.textContaining('2026-11-22'), findsWidgets);

    // 只有 11 号那笔是"今天补录"
    expect(find.textContaining('补录 11 天'), findsOneWidget);
    expect(find.textContaining('本区间有 1 笔是今天补录的'), findsOneWidget);

    // 补录行直接给出录入时刻（MM-DD HH:mm）
    expect(find.textContaining('录入 11-22 16:32'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点补录行可以看到精确到秒的录入时间', (tester) async {
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

    await tester.tap(find.textContaining('补录 11 天'));
    await settle(tester);

    expect(find.text('计件时间详情'), findsOneWidget);
    expect(find.text('归属日期'), findsOneWidget);
    expect(find.text('录入时间'), findsOneWidget);
    expect(find.text('2026-11-22 16:32:41'), findsOneWidget);
    // 弹窗里明确写出"账算在 11 号、不会算到今天"
    expect(find.textContaining('不会算到今天'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('知道了'));
    await settle(tester);
  });

  testWidgets('法定假期在日期分组上有角标', (tester) async {
    useTallView(tester);
    // 真库 IO 必须走 runAsync，否则假时钟下永远等不到
    final toy = await tester.runAsync(
      () => f.addToy('小兔', priceTenThousandth: 1000),
    );
    await tester.runAsync(
      () => f.records.create(
        date: '2026-10-01',
        worker: zhang,
        toy: toy!,
        quantity: 10,
      ),
    );

    await tester.pumpWidget(
      wrap(
        WorkerRecordsPage(
          workerId: zhang.id,
          workerName: zhang.name,
          workerCode: zhang.code,
          range: const DateRange(start: '2026-10-01', end: '2026-10-31'),
        ),
      ),
    );
    await settle(tester);

    expect(find.textContaining('国庆节'), findsWidgets);
    expect(find.textContaining('2026-10-01'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('超大字号下补录行不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(
        WorkerRecordsPage(
          workerId: zhang.id,
          workerName: '张三（临时工）',
          workerCode: zhang.code,
          range: const DateRange(start: '2026-11-01', end: '2026-11-30'),
        ),
        textScale: 1.6,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '补录标记在超大字号下溢出了');
    expect(find.textContaining('补录'), findsWidgets);
  });
}
