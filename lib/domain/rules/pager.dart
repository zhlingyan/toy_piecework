/// 列表分页口径：把「总数 / 每页条数 / 当前页」收敛成边界安全的切片。
///
/// 为什么单独抽出来：
/// * 「第几页」是用户态，翻页、改每页条数、改搜索词都会让它失效，
///   若各页面各写一遍 `~/` 和 `%`，迟早出现「最后一页空白」
///   「切到 50 条后页码还停在 5/2」这类越界；
/// * 0 条数据时页数必须是 1（而不是 0），否则「第 1/0 页」会算出负数下标。
///
/// 这里只做纯计算，不碰界面，方便用单元测试钉住边界。
class Pager {
  const Pager._({
    required this.total,
    required this.pageSize,
    required this.page,
  });

  /// 每页条数档位。10 条适合核对、50 条适合快速扫一遍。
  static const List<int> pageSizes = [10, 20, 50];

  /// 默认每页 20 条。
  static const int defaultPageSize = 20;

  factory Pager.of({
    required int total,
    required int pageSize,
    required int page,
  }) {
    final size = pageSize > 0 ? pageSize : defaultPageSize;
    final safeTotal = total < 0 ? 0 : total;
    final pages = pageCountOf(safeTotal, size);
    var safePage = page;
    if (safePage < 0) safePage = 0;
    if (safePage > pages - 1) safePage = pages - 1;
    return Pager._(total: safeTotal, pageSize: size, page: safePage);
  }

  static int pageCountOf(int total, int pageSize) {
    if (total <= 0) return 1;
    return (total + pageSize - 1) ~/ pageSize;
  }

  final int total;
  final int pageSize;

  /// 从 0 开始的当前页。
  final int page;

  int get pageCount => pageCountOf(total, pageSize);

  /// 给人看的页码（从 1 开始）。
  int get pageNumber => page + 1;

  bool get hasPrev => page > 0;
  bool get hasNext => page < pageCount - 1;

  /// 当前页第一条在整体列表中的下标（0 条时为 0）。
  int get start => total == 0 ? 0 : page * pageSize;

  /// 当前页最后一条的下一位（左闭右开）。
  int get end {
    final raw = start + pageSize;
    return raw > total ? total : raw;
  }

  /// 当前页实际条数。
  int get length => end > start ? end - start : 0;

  /// 截取当前页。列表长度与 [total] 不一致时也不抛异常。
  List<T> slice<T>(List<T> items) {
    if (items.isEmpty) return const [];
    final from = start > items.length ? items.length : start;
    final to = end > items.length ? items.length : end;
    if (from >= to) return const [];
    return items.sublist(from, to);
  }

  /// 换每页条数：页码必须回到第一页，否则会落在越界的空白页上。
  Pager withPageSize(int size) =>
      Pager.of(total: total, pageSize: size, page: 0);

  Pager withPage(int index) =>
      Pager.of(total: total, pageSize: pageSize, page: index);

  Pager next() => hasNext ? withPage(page + 1) : this;

  Pager previous() => hasPrev ? withPage(page - 1) : this;
}
