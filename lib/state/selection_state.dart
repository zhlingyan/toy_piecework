import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';

/// 跨页面共享的录入上下文。
///
/// 全部用固定 id 保存选中状态（严禁用列表下标），
/// 这样新增/归档档案后选中对象不会串位。
class SelectionState extends ChangeNotifier {
  String _date = Dates.ymd(DateTime.now());

  /// 录入日期，`YYYY-MM-DD`。
  String get date => _date;

  set date(String value) {
    if (!Dates.isValidYmd(value)) return;
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

  set tabIndex(int value) {
    if (_tabIndex == value) return;
    _tabIndex = value;
    notifyListeners();
  }
}
