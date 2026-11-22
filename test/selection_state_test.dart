import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/state/selection_state.dart';

/// 「马上计数」每次进入都要回到今天，但不能在补录途中被悄悄改掉。
void main() {
  final now = DateTime(2026, 11, 22, 9, 15);

  setUp(() => AppClock.override(() => now));
  tearDown(AppClock.reset);

  test('默认日期是今天', () {
    final selection = SelectionState();
    expect(selection.date, '2026-11-22');
    expect(selection.isToday, isTrue);
    expect(selection.tabIndex, 0);
  });

  test('从别的页签进入计数页：日期回到今天', () {
    final selection = SelectionState();
    selection.date = '2026-11-11';
    expect(selection.isToday, isFalse);

    selection.tabIndex = 1;
    expect(selection.tabIndex, 1);
    expect(selection.date, '2026-11-22');
    expect(selection.isToday, isTrue);
  });

  test('已经在计数页时再次点计数页签：不重置（补录中误触也不会丢日期）', () {
    final selection = SelectionState();
    selection.tabIndex = 1;
    selection.date = '2026-11-11';

    // 重复点同一个页签
    selection.tabIndex = 1;
    expect(selection.date, '2026-11-11');

    // 手动调 selectTab(1) 同理
    selection.selectTab(1);
    expect(selection.date, '2026-11-11');
  });

  test('离开再回来：重新回到今天', () {
    final selection = SelectionState();
    selection.tabIndex = 1;
    selection.date = '2026-11-11';

    selection.tabIndex = 2; // 去结算
    expect(selection.date, '2026-11-11', reason: '去别的页不该动计数页的日期');

    selection.tabIndex = 1; // 回计数
    expect(selection.date, '2026-11-22');
  });

  test('resetDateToToday 生效且只通知一次', () {
    final selection = SelectionState();
    selection.date = '2026-11-11';
    var notified = 0;
    selection.addListener(() => notified++);

    selection.resetDateToToday();
    expect(selection.date, '2026-11-22');
    expect(notified, 1);

    // 已经是今天，再调不通知
    selection.resetDateToToday();
    expect(notified, 1);
  });

  test('非法日期被拒绝，不会把状态写坏', () {
    final selection = SelectionState();
    selection.date = '2026-02-30';
    expect(selection.date, '2026-11-22');
    selection.date = '';
    expect(selection.date, '2026-11-22');
  });

  test('负数页签不会把导航搞坏', () {
    final selection = SelectionState();
    selection.selectTab(-1);
    expect(selection.tabIndex, 0);
    expect(selection.date, '2026-11-22');
  });
}
