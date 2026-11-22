import 'package:material_ui/material_ui.dart';

import '../core/clock.dart';
import '../core/dates.dart';

/// 跨页面共享的录入上下文。
///
/// 全部用固定 id 保存选中状态（严禁用列表下标），
/// 这样新增/归档档案后选中对象不会串位。
class SelectionState extends ChangeNotifier {
  /// 计数页在底部导航里的下标。
  static const int countTabIndex = 1;

  String _date = Dates.ymd(AppClock.now());

  /// 录入日期，`YYYY-MM-DD`。
  ///
  /// 这是**业务日期**：记账时写进 `records.date`，决定这笔活算哪一天。
  String get date => _date;

  set date(String value) {
    if (!Dates.isValidYmd(value)) return;
    if (_date == value) return;
    _date = value;
    notifyListeners();
  }

  /// 今天（`YYYY-MM-DD`）。
  static String get today => Dates.ymd(AppClock.now());

  /// 当前录入日期是不是今天。
  bool get isToday => _date == today;

  /// 把录入日期重置为今天。
  ///
  /// 「马上计数」是当下掏手机就记，不该继承上次补录留下的旧日期。
  void resetDateToToday() {
    final value = today;
    if (_date == value) return;
    _date = value;
    notifyListeners();
  }

  String? _workerId;

  /// 当前选中工人 id。
  String? get workerId => _workerId;

  set workerId(String? value) {
    if (_workerId == value) return;
    _workerId = value;
    notifyListeners();
  }

  String? _toyId;

  /// 当前选中玩具（工序）id。
  String? get toyId => _toyId;

  set toyId(String? value) {
    if (_toyId == value) return;
    _toyId = value;
    notifyListeners();
  }

  int _tabIndex = 0;

  int get tabIndex => _tabIndex;

  /// 直接设置页签。会走 [selectTab] 的同一套规则（进入计数页回到今天）。
  set tabIndex(int value) => selectTab(value);

  /// 切换底部页签。
  ///
  /// **从别的页签进入「计数」时把录入日期重置为今天**：
  /// 计数页常驻在 `IndexedStack` 里，如果沿用上次补录的旧日期，
  /// 第二天照着记就会静默记到昨天甚至更早——这是最难发现的错账来源。
  ///
  /// 已经停在计数页时（`_tabIndex == 1` 且目标也是 1）**不重置**，
  /// 否则用户在补录过程中误触页签，日期会被悄悄改回今天。
  void selectTab(int value) {
    if (value < 0) return;
    var changed = false;
    if (value == countTabIndex && _tabIndex != countTabIndex) {
      final today = SelectionState.today;
      if (_date != today) {
        _date = today;
        changed = true;
      }
    }
    if (_tabIndex != value) {
      _tabIndex = value;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
