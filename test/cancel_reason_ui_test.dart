import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/settlement_event.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/ui/settlement/worker_detail_sheet.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 问题 17：取消理由选填、当前状态标识、完整变更历史（时间不覆盖）。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker worker;
  final nov = DateRange.of('2026-11-01', '2026-11-30');

  setUp(() async {
    AppClock.override(() => DateTime(2026, 11, 22, 9, 30, 5));
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    services = AppServices(db: f.db, settings: await AppSettings.load());
    worker = await f.addWorker('张三', code: 'W001');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-11-05',
      worker: worker,
      toy: toy,
      quantity: 100,
    );
    // 升级前已标记一次已结算（历史第 1 条）
    await f.settlementEntries.markRange(
      workerId: worker.id,
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

  Future<void> pumpDetail(WidgetTester tester) async {
    // tester.runAsync：sqflite 的真实 IO 不能在 fake-async 里直接 await。
    final result = await tester.runAsync(() => f.settlements.settle(nov));
    final fresh = result!.workers.single;
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => FilledButton(
                  key: const ValueKey('open-detail'),
                  onPressed: () async {
                    await showWorkerDetailSheet(
                      context: ctx,
                      services: services,
                      worker: fresh,
                      range: nov,
                    );
                  },
                  child: const Text('打开详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('open-detail')));
    await settle(tester);
  }

  testWidgets('取消已结算弹选填理由框，留空也能完成，状态标识实时刷新',
      (tester) async {
    useTallView(tester);
    await pumpDetail(tester);

    expect(find.byKey(const ValueKey('detail-status-trail')), findsOneWidget);
    expect(find.text('当前状态：已结算'), findsOneWidget);
    expect(find.textContaining('共 1 次变更'), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-open-history')), findsOneWidget);

    AppClock.override(() => DateTime(2026, 11, 22, 10, 15, 30));
    await tester.tap(find.text('取消已结算'));
    await settle(tester);

    expect(find.byKey(const ValueKey('cancel-reason-input')), findsOneWidget);
    expect(find.text('（选填，可留空）'), findsOneWidget);
    expect(find.textContaining('留空也能完成取消'), findsOneWidget);

    // 理由留空，直接确认
    await tester.tap(find.byKey(const ValueKey('cancel-reason-confirm')));
    await settle(tester);

    expect(find.text('当前状态：未结算'), findsOneWidget);
    expect(find.textContaining('共 2 次变更'), findsOneWidget);

    final events = await tester.runAsync(
      () => f.settlementHistory.listForWorker(worker.id),
    );
    expect(events!.length, 2);
    expect(events.first.action, SettlementAction.unsettled);
    expect(events.first.reason, '');
    expect(events.first.happenedAt, '2026-11-22 10:15:30');
    expect(events.last.happenedAt, '2026-11-22 09:30:05',
        reason: '第一次的时间戳不能被覆盖');
    expect(tester.takeException(), isNull);
  });

  testWidgets('填写 / 快捷选择取消理由会写入历史，理由不强制', (tester) async {
    useTallView(tester);
    await pumpDetail(tester);

    await tester.tap(find.text('取消已结算'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ActionChip, '算错金额，重结'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cancel-reason-confirm')));
    await settle(tester);

    final events = await tester.runAsync(
      () => f.settlementHistory.listForWorker(worker.id),
    );
    expect(events!.length, 2);
    expect(events.first.reason, '算错金额，重结');
    expect(events.first.hasReason, isTrue);
    expect(events.last.reason, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('变更历史面板展示完整追加流与当前状态，时间不覆盖',
      (tester) async {
    // 再追加一条取消（带理由），变成 2 条
    AppClock.override(() => DateTime(2026, 11, 22, 11, 0, 0));
    await tester.runAsync(() => f.settlementEntries.markRange(
          workerId: worker.id,
          months: const ['2026-11'],
          range: nov,
          settled: false,
          reason: '工人有异议',
        ));

    useTallView(tester);
    await pumpDetail(tester);
    await tester.tap(find.byKey(const ValueKey('detail-open-history')));
    await settle(tester);

    expect(find.byKey(const ValueKey('history-current-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-list')), findsOneWidget);
    // 详情卡片与历史面板顶部都显示当前状态标识，属正常重复
    expect(find.textContaining('共 2 次变更'), findsWidgets);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('取消结算'), findsOneWidget);
    expect(find.textContaining('取消理由：工人有异议'), findsOneWidget);
    expect(find.textContaining('2026-11-22 11:00:00'), findsWidgets);
    // 第 1 条仍在，时间没被后来的操作改写
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('结算'), findsOneWidget);
    expect(find.textContaining('2026-11-22 09:30:05'), findsOneWidget);
    expect(find.textContaining('打印总表'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
