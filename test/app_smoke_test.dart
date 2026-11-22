import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toy_piecework/app.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/models/worker.dart';
import 'package:toy_piecework/services/app_services.dart';
import 'package:toy_piecework/services/app_settings.dart';
import 'package:toy_piecework/state/selection_state.dart';
import 'package:toy_piecework/ui/archives/worker_profile_page.dart';
import 'package:toy_piecework/ui/reports/annual_page.dart';
import 'package:toy_piecework/ui/settings/cloud_backup_page.dart';
import 'package:toy_piecework/ui/theme.dart';

import 'support/fixture.dart';

/// 界面冒烟测试：用真实数据把页面渲染一遍，确保没有布局崩溃与生命周期错误。
///
/// 业务逻辑已有 80+ 条单测覆盖，这里只验证「界面能建出来」这条底线。
///
/// 注意：页面在 `didChangeDependencies` 里发起真实数据库查询，
/// 而 `pumpAndSettle` 用的是假时钟，两者混用会卡死。
/// 因此统一用 [_settle]：先让真实异步跑完，再手动推帧。
void main() {
  late Fixture f;
  late AppServices services;
  late Worker zhang;

  setUp(() async {
    f = await Fixture.create();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    services = AppServices(db: f.db, settings: settings);

    zhang = await f.addWorker('张三');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: Dates.ymd(DateTime.now()),
      worker: zhang,
      toy: toy,
      quantity: 500,
    );
  });

  tearDown(() async {
    await f.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    // 让 sqflite 的真实异步（跑在事件循环上）完成
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  }

  /// 单独渲染一个子页面（带 AppScope 与主题）。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        refresh: services.refresh,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: page,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('四个页签都能正常渲染', (tester) async {
    final selection = SelectionState();
    await tester.pumpWidget(
      ToyPieceworkApp(services: services, selection: selection),
    );
    await settle(tester);

    // 概览：今日 500 件 × 0.20 = 100.00
    expect(find.text('今日计件总额'), findsOneWidget);
    expect(find.text('100.00'), findsWidgets);

    // 计数
    selection.tabIndex = 1;
    await settle(tester);
    expect(find.text('改日期'), findsOneWidget);

    // 结算
    selection.tabIndex = 2;
    await settle(tester);
    expect(find.text('应付合计'), findsOneWidget);
    expect(find.text('张三'), findsWidgets);

    // 设置
    selection.tabIndex = 3;
    await settle(tester);
    expect(find.text('档案管理'), findsOneWidget);

    // 卸载页面后再关库，避免页面在库关闭后还在查询
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('选中状态按 id 保存：新增档案不会改变已选工人', (tester) async {
    final selection = SelectionState();
    await tester.pumpWidget(
      ToyPieceworkApp(services: services, selection: selection),
    );
    await settle(tester);

    selection.workerId = zhang.id;
    await settle(tester);
    expect(selection.workerId, zhang.id);

    // 插入编号更靠前的工人，列表顺序会变，但选中 id 不能变
    await tester.runAsync(() => f.addWorker('阿一', code: 'W000'));
    services.notifyDataChanged();
    await settle(tester);

    expect(selection.workerId, zhang.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('年度报表页：统计与工人明细', (tester) async {
    await pumpPage(tester, const AnnualPage());

    expect(find.text('年度报表'), findsOneWidget);
    expect(find.text('年产量'), findsOneWidget);
    expect(find.text('年工资'), findsOneWidget);
    expect(find.text('张三'), findsWidgets);
    // 500 件 → 100.00 元
    expect(find.text('500 件 · 1 项工序'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('员工档案页：累计数据与时间线', (tester) async {
    await pumpPage(tester, WorkerProfilePage(worker: zhang));

    expect(find.text('累计产量'), findsOneWidget);
    expect(find.text('累计工资'), findsOneWidget);
    expect(find.text('做过的玩具'), findsOneWidget);
    expect(find.text('每日时间线'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('云备份页：未配置账号时也能正常显示', (tester) async {
    await pumpPage(tester, const CloudBackupPage());

    expect(find.text('备份状态'), findsOneWidget);
    expect(find.text('从未备份'), findsOneWidget);
    expect(find.text('保存并测试连接'), findsOneWidget);
    // 网址默认填好坚果云地址
    expect(find.text('https://dav.jianguoyun.com/dav/'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
