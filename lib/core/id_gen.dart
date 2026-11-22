import 'package:uuid/uuid.dart';

/// 主键生成。TEXT 主键，永不复用，便于跨设备/备份合并。
class IdGen {
  IdGen._();

  static const Uuid _uuid = Uuid();

  static String next() => _uuid.v4();

  /// 连录防重复：界面在「点击保存」时先生成 id，
  /// 双击产生的第二次写入因主键冲突被忽略，从数据库层兜住重复提交。
  static String nextRecordId() => _uuid.v4();
}
