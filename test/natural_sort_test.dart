import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/domain/rules/natural_sort.dart';

/// 自然序比较：工号里带数字时不能按纯字典序排。
void main() {
  test('数字段按数值比较，A2 在 A10 前、002 在 010 前', () {
    expect(naturalCompare('A2', 'A10'), lessThan(0));
    expect(naturalCompare('A10', 'A2'), greaterThan(0));
    expect(naturalCompare('002', '010'), lessThan(0));
    expect(naturalCompare('W9', 'W10'), lessThan(0));
    expect(naturalCompare('W001', 'W002'), lessThan(0));
    expect(naturalCompare('W2', 'W10'), lessThan(0));
  });

  test('大小写不敏感、相同字符串为 0、前缀短的在前', () {
    expect(naturalCompare('a2', 'A10'), lessThan(0));
    expect(naturalCompare('a2', 'A2'), 0);
    expect(naturalCompare('A2', 'A2'), 0);
    expect(naturalCompare('A1', 'A1-2'), lessThan(0));
    expect(naturalCompare('', 'A1'), lessThan(0));
  });

  test('超长数字也不溢出（按去零后的长度与字典序比）', () {
    expect(
      naturalCompare('99999999999999999999', '100000000000000000000'),
      lessThan(0),
    );
    expect(naturalCompare('0000000002', '10'), lessThan(0));
  });

  test('全零段与中文混合都不抛异常', () {
    expect(naturalCompare('000', '0'), 0);
    expect(naturalCompare('张三2号', '张三10号'), lessThan(0));
    expect(naturalCompare('A-2', 'A-10'), lessThan(0));
  });
}
