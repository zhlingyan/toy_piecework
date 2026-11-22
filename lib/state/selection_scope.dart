import 'package:material_ui/material_ui.dart';

import 'selection_state.dart';

/// 让任意页面都能拿到录入上下文（选中工人/工序/日期）。
class SelectionScope extends InheritedNotifier<SelectionState> {
  const SelectionScope({
    super.key,
    required this.selection,
    required super.child,
  }) : super(notifier: selection);

  final SelectionState selection;

  static SelectionState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SelectionScope>();
    assert(scope != null, '缺少 SelectionScope');
    return scope!.selection;
  }

  static SelectionState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionScope>()?.selection;

  /// 在回调里切换 tab、设置选中项时使用，不建立依赖。
  static SelectionState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SelectionScope>()?.selection;
}
