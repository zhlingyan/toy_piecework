import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/domain/rules/pager.dart';

/// 分页口径的边界：0 条、正好整页、最后一页不满、页码越界、换档位。
void main() {
  test('0 条数据：页数为 1，切片为空，页码不出现负数', () {
    final pager = Pager.of(total: 0, pageSize: 20, page: 0);
    expect(pager.pageCount, 1);
    expect(pager.pageNumber, 1);
    expect(pager.start, 0);
    expect(pager.end, 0);
    expect(pager.length, 0);
    expect(pager.slice(const []), isEmpty);
    expect(pager.hasPrev, isFalse);
    expect(pager.hasNext, isFalse);
  });

  test('12 条 / 每页 10：2 页，第二页只有 2 条', () {
    final first = Pager.of(total: 12, pageSize: 10, page: 0);
    expect(first.pageCount, 2);
    expect(first.start, 0);
    expect(first.end, 10);
    expect(first.hasNext, isTrue);
    expect(first.hasPrev, isFalse);

    final second = Pager.of(total: 12, pageSize: 10, page: 1);
    expect(second.start, 10);
    expect(second.end, 12);
    expect(second.length, 2);
    expect(second.hasNext, isFalse);
    expect(second.hasPrev, isTrue);
  });

  test('正好整页时不多出一页空白', () {
    final pager = Pager.of(total: 40, pageSize: 20, page: 1);
    expect(pager.pageCount, 2);
    expect(pager.pageNumber, 2);
    expect(pager.hasNext, isFalse);
  });

  test('页码越界自动收敛到最后一页', () {
    final pager = Pager.of(total: 25, pageSize: 10, page: 9);
    expect(pager.pageCount, 3);
    expect(pager.page, 2);
    expect(pager.start, 20);
    expect(pager.end, 25);

    final negative = Pager.of(total: 25, pageSize: 10, page: -3);
    expect(negative.page, 0);
  });

  test('换每页条数后回到第一页，避免落在空白页', () {
    final pager = Pager.of(total: 45, pageSize: 10, page: 4);
    expect(pager.page, 4);
    final resized = pager.withPageSize(50);
    expect(resized.pageSize, 50);
    expect(resized.page, 0);
    expect(resized.pageCount, 1);
    expect(resized.slice(List.generate(45, (i) => i)).length, 45);
  });

  test('列表长度与 total 不一致（刚删完一条）也不抛异常', () {
    final pager = Pager.of(total: 30, pageSize: 10, page: 2);
    final slice = pager.slice(List.generate(21, (i) => i));
    expect(slice.length, 1);
  });

  test('非法每页条数回落到默认 20', () {
    final pager = Pager.of(total: 5, pageSize: 0, page: 0);
    expect(pager.pageSize, Pager.defaultPageSize);
    expect(pager.pageCount, 1);
  });
}
