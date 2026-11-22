/// 自然序（数值感知）字符串比较。
///
/// 纯字典序会把 `A10` 排在 `A2` 前、`010` 排在 `002` 前——车间工号里
/// 数字一多就非常反直觉。这里把字符串切成「数字段 / 非数字段」：
/// * 两段都是数字 → **按数值**比（先去前导零、比长度、再比字典序，
///   天然支持超长数字，不会 int 溢出）；
/// * 否则按字符序比；
/// * 前缀完全相同时，段数少的排前面。
///
/// 大小写不敏感（`a10` 与 `A10` 视为同级），空串按普通字符串规则排在最前，
/// 调用方若要「空工号排最后」需自行处理（见 `worker_sort.dart`）。
int naturalCompare(String a, String b) {
  final left = _tokenize(a.toUpperCase());
  final right = _tokenize(b.toUpperCase());
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final x = left[i];
    final y = right[i];
    final cmp = (x.isNumeric && y.isNumeric)
        ? _compareNumeric(x.text, y.text)
        : x.text.compareTo(y.text);
    if (cmp != 0) return cmp;
  }
  return left.length.compareTo(right.length);
}

class _Chunk {
  const _Chunk(this.text, this.isNumeric);

  final String text;
  final bool isNumeric;
}

List<_Chunk> _tokenize(String value) {
  final chunks = <_Chunk>[];
  final buffer = StringBuffer();
  bool? numeric;
  for (final unit in value.codeUnits) {
    final isDigit = unit >= 48 && unit <= 57; // '0'..'9'
    if (numeric != null && isDigit != numeric) {
      chunks.add(_Chunk(buffer.toString(), numeric));
      buffer.clear();
    }
    numeric = isDigit;
    buffer.writeCharCode(unit);
  }
  if (buffer.isNotEmpty) {
    chunks.add(_Chunk(buffer.toString(), numeric ?? false));
  }
  return chunks;
}

/// 比较两个「纯数字」段：去掉前导零后，短的更小；等长再按字典序。
/// 全零段（如 `000` 与 `0`）视为相等，交给调用方的稳定兜底键决定顺序。
int _compareNumeric(String a, String b) {
  final x = a.replaceFirst(RegExp(r'^0+'), '');
  final y = b.replaceFirst(RegExp(r'^0+'), '');
  if (x.isEmpty && y.isEmpty) return 0;
  if (x.isEmpty) return -1;
  if (y.isEmpty) return 1;
  if (x.length != y.length) return x.length.compareTo(y.length);
  return x.compareTo(y);
}
