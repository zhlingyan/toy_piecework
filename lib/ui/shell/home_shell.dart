import 'package:material_ui/material_ui.dart';

import '../../services/app_services.dart';
import '../../state/selection_state.dart';
import '../count/count_page.dart';
import '../overview/overview_page.dart';
import '../settlement/settlement_page.dart';
import '../settings/settings_page.dart';
import '../theme.dart';

/// 四大主入口：概览 / 计数 / 结算 / 设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.selection});

  final SelectionState selection;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const OverviewPage(),
      CountPage(selection: widget.selection),
      SettlementPage(selection: widget.selection),
      const SettingsPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return AnimatedBuilder(
      animation: widget.selection,
      builder: (context, _) {
        final index = widget.selection.tabIndex;
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) widget.selection.tabIndex = 0;
          },
          child: Scaffold(
            body: IndexedStack(index: index, children: _pages),
            bottomNavigationBar: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: BottomNavigationBar(
                  currentIndex: index,
                  onTap: (value) {
                    widget.selection.tabIndex = value;
                    // 切页时刷新数据，保证跨页操作（新增档案/改单）立刻可见
                    services.notifyDataChanged();
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.dashboard_outlined),
                      activeIcon: Icon(Icons.dashboard),
                      label: '概览',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.add_circle_outline, size: 28),
                      activeIcon: Icon(Icons.add_circle, size: 28),
                      label: '计数',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.receipt_long_outlined),
                      activeIcon: Icon(Icons.receipt_long),
                      label: '结算',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings_outlined),
                      activeIcon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
