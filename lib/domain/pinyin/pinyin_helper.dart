import 'pinyin_table.dart';

/// 离线拼音首字母工具（零依赖、零网络）。
///
/// 用途：
/// * 建档时自动算出首字母，支持「ZS」搜「张三」；
/// * 列表按 A–Z 分组，数字/符号开头归 `#`；
/// * 多音姓氏做优先映射（单→S、曾→Z、解→X、查→Z、仇→Q、区→O …），
///   并允许在档案页手工修正。
class PinyinHelper {
  PinyinHelper._();

  /// 多音姓氏首字母优先表：只收录「姓氏读音与常用读音首字母不同」的字。
  static const Map<String, String> kSurnameInitials = {
    '单': 'S', '曾': 'Z', '解': 'X', '查': 'Z', '仇': 'Q', '区': 'O',
    '尉': 'Y', '种': 'C', '盖': 'G', '万': 'M', '车': 'C', '长': 'C',
    '黑': 'H', '朴': 'P', '折': 'S', '乐': 'Y', '缪': 'M', '句': 'G',
    '秘': 'B', '员': 'Y', '燕': 'Y', '华': 'H', '过': 'G', '宁': 'N',
    '藏': 'Z', '翟': 'Z', '隗': 'W', '繁': 'P', '番': 'P', '郇': 'X',
    '郗': 'X', '那': 'N', '召': 'S', '佴': 'N', '阚': 'K', '逄': 'P',
    '璩': 'Q', '雒': 'L', '芈': 'M', '乜': 'N', '厍': 'S', '禚': 'Z',
    '爨': 'C', '澹': 'T', '笪': 'D', '缑': 'G', '亢': 'K', '蒯': 'K',
    '郐': 'K', '郦': 'L', '蔺': 'L', '甯': 'N', '亓': 'Q', '谯': 'Q',
    '覃': 'Q', '麴': 'Q', '饶': 'R', '汝': 'R', '芮': 'R', '莘': 'S',
    '眭': 'S', '睢': 'S', '仉': 'Z', '邝': 'K', '亳': 'B', '阡': 'Q',
  };

  static Map<int, String>? _index;

  static Map<int, String> get _map {
    var map = _index;
    if (map != null) return map;
    map = <int, String>{};
    kInitialCharTable.forEach((letter, chars) {
      for (final rune in chars.runes) {
        map![rune] = letter;
      }
    });
    _index = map;
    return map;
  }

  /// 取首字母串。
  ///
  /// * 汉字 → 首字母
  /// * 英文字母 → 原样大写
  /// * 数字 → 原样保留（用于「李四2号」这类编号）
  /// * 其它符号与空格 → 跳过
  ///
  /// [asName] 为 true 时，首个汉字套用多音姓氏优先表。
  static String initialsOf(String text, {bool asName = true}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final buffer = StringBuffer();
    var isFirst = true;
    for (final rune in trimmed.runes) {
      final char = String.fromCharCode(rune);
      if (_isSpace(rune)) continue;
      if (isFirst && asName) {
        final override = kSurnameInitials[char];
        if (override != null) {
          buffer.write(override);
          isFirst = false;
          continue;
        }
      }
      if (rune >= 0x41 && rune <= 0x5A) {
        buffer.write(char);
      } else if (rune >= 0x61 && rune <= 0x7A) {
        buffer.write(char.toUpperCase());
      } else if (rune >= 0x30 && rune <= 0x39) {
        buffer.write(char);
      } else {
        final letter = _map[rune];
        if (letter != null) buffer.write(letter);
      }
      isFirst = false;
    }
    return buffer.toString();
  }

  /// 列表分组键：A–Z，其它归 `#`。
  static String groupKey(String initials) {
    if (initials.isEmpty) return '#';
    final first = initials.codeUnitAt(0);
    if (first >= 0x41 && first <= 0x5A) {
      return initials[0];
    }
    return '#';
  }

  /// 把档案按首字母分组，A–Z 升序、`#` 放最后。组内按 [code] 再按名称排序。
  static Map<String, List<T>> groupByInitial<T>(
    Iterable<T> items, {
    required String Function(T item) initialsOf,
    required String Function(T item) codeOf,
    required String Function(T item) nameOf,
  }) {
    final groups = <String, List<T>>{};
    for (final item in items) {
      final key = groupKey(initialsOf(item));
      groups.putIfAbsent(key, () => []).add(item);
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        final byCode = codeOf(a).compareTo(codeOf(b));
        if (byCode != 0) return byCode;
        return nameOf(a).compareTo(nameOf(b));
      });
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final key in keys) key: groups[key]!};
  }

  /// 中文 + 首字母混合搜索。
  ///
  /// 规则：名称包含、编号包含、首字母前缀命中任一即算匹配。
  static bool matches({
    required String query,
    required String name,
    String initials = '',
    String code = '',
  }) {
    final q = query.trim();
    if (q.isEmpty) return true;
    if (name.contains(q)) return true;
    if (code.isNotEmpty && code.toUpperCase().contains(q.toUpperCase())) return true;
    if (initials.isNotEmpty && initials.startsWith(q.toUpperCase())) return true;
    return false;
  }

  static bool _isSpace(int rune) =>
      rune == 0x20 || rune == 0x3000 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
}
