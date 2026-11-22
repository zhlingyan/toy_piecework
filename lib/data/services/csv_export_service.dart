import '../models/piece_record.dart';
import '../models/settlement.dart';
import '../../core/money.dart';

/// CSV 导出：带 UTF-8 BOM，Excel 直接双击不乱码。
///
/// 金额列一律输出两位小数的「元」，方便财务直接求和；
/// 单价列按实际精度输出（最多 4 位小数）。
class CsvExportService {
  const CsvExportService();

  static const String bom = '\uFEFF';
  static const String lineEnding = '\r\n';

  /// 打印/导出「总表」的**正式字段白名单**。
  ///
  /// 只从 `SettlementResult` 的正式汇总字段取数，
  /// `settlement_history` 表完全不参与结算 Csv 的任何查询：
  /// 变更历史、时间戳、取消理由在架构上就进不来。
  static const List<String> settlementPrintColumns = [
    '工人编号',
    '工人',
    '计件工资(元)',
    '补贴(元)',
    '计时(元)',
    '扣款(元)',
    '预支(元)',
    '应付(元)',
    '加班件数',
    '其中加班工资(元)',
    '说明',
    '结算状态',
  ];

  /// 只追加的审计字段：白名单之外，一律不出现在总表里。
  static const Set<String> auditOnlyFields = {
    '取消理由',
    '变更历史',
    '状态变更时间',
    '结算时间戳',
    '取消结算时间',
    '状态变更记录',
    'reason',
    'happened_at',
    'settlement_history',
    'seq',
  };

  /// 打印总表的最后一道清洗：即便有人在备注里手打了审计信息，
  /// 也从输出文本中剔除时间戳、取消理由、变更历史与追加标识。
  ///
  /// 只用于**正式总表文本列**，不用于历史面板（那里要完整展示）。
  static String stripAuditMetadata(String value) {
    var text = value;
    // 「取消理由：xxx」「变更历史：xxx」等审计短语（到换行/逗号/分号为止）。
    text = text.replaceAll(
      RegExp(r'(取消理由|变更历史|状态变更时间|结算时间戳|取消结算时间|状态变更记录)\s*[：:]\s*[^\r\n,，;；]*'),
      '',
    );
    // 精确到秒的时间戳 YYYY-MM-DD HH:mm:ss。
    text = text.replaceAll(
      RegExp(r'\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}:\d{2}'),
      '',
    );
    // 追加标识「#12 结算 / 取消结算」。
    text = text.replaceAll(
      RegExp(r'#\d+\s*(结算|取消结算)'),
      '',
    );
    // 清理被剔除后残留的连续分隔符，保持单元格清爽。
    text = text.replaceAll(RegExp(r'(?:\s*[·|,，;；]\s*){2,}'), ' ');
    return text.trim();
  }

  /// 字段转义：含逗号/引号/换行时用双引号包裹，内部引号翻倍。
  static String escape(String value) {
    final needsQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  String _row(List<String> cells) =>
      cells.map(escape).join(',') + lineEnding;

  /// 计件流水明细。
  String recordsCsv(List<PieceRecord> records) {
    final buffer = StringBuffer(bom);
    buffer.write(_row([
      '日期',
      '工人',
      '玩具',
      '工序',
      '单价(元)',
      '数量',
      '小计(元)',
      '备注',
    ]));
    for (final record in records) {
      buffer.write(_row([
        record.date,
        record.workerNameSnapshot,
        record.toyNameSnapshot,
        record.processSnapshot,
        Money.formatPrice(record.unitPriceSnapshot),
        '${record.quantity}',
        Money.formatCents(record.subtotalCents),
        record.remark,
      ]));
    }
    return buffer.toString();
  }

  /// 结算汇总（一人一行），末行为合计。
  ///
  /// 表头固定取 [settlementPrintColumns] 白名单；所有文本列过一遍
  /// [stripAuditMetadata]，确保总表只有正式结算汇总信息。
  String settlementCsv(SettlementResult result) {
    final buffer = StringBuffer(bom);
    buffer.write(_row(settlementPrintColumns));
    for (final worker in result.workers) {
      // 加班单独列出来，方便核对「这个月加了多少班、多拿了多少」
      final overtimeQuantity = worker.groups
          .where((group) => group.overtime)
          .fold(0, (sum, group) => sum + group.quantity);
      final overtimeCents = worker.groups
          .where((group) => group.overtime)
          .fold(0, (sum, group) => sum + group.subtotalCents);
      buffer.write(_row([
        stripAuditMetadata(worker.workerCode),
        stripAuditMetadata(worker.workerName),
        Money.formatCents(worker.pieceCents),
        Money.formatCents(worker.bonusCents),
        Money.formatCents(worker.hourlyCents),
        Money.formatCents(worker.deductionCents),
        Money.formatCents(worker.advanceCents),
        Money.formatCents(worker.netCents),
        '$overtimeQuantity',
        Money.formatCents(overtimeCents),
        stripAuditMetadata(worker.isArchived ? '已停用档案' : ''),
        stripAuditMetadata(worker.settlementStatus.label),
      ]));
    }
    buffer.write(_row([
      '',
      '合计',
      Money.formatCents(result.totalPieceCents),
      Money.formatCents(result.bonusTotal),
      Money.formatCents(result.hourlyTotal),
      Money.formatCents(result.deductionTotal),
      Money.formatCents(result.advanceTotal),
      Money.formatCents(result.totalNetCents),
      '',
      '',
      stripAuditMetadata('${result.range.label}，逐笔取整后合计'),
      '未结 ${Money.formatCents(result.unsettledTotalCents)}',
    ]));
    return buffer.toString();
  }

  /// 年度报告（工人 × 玩具 × 工序）。
  String annualCsv({
    required int year,
    required List<({String workerId, String workerName, String toyName, String process, int quantity, int cents})> rows,
  }) {
    final buffer = StringBuffer(bom);
    buffer.write(_row(['年份', '工人', '玩具', '工序', '年产量(件)', '年工资(元)']));
    for (final row in rows) {
      buffer.write(_row([
        '$year',
        row.workerName,
        row.toyName,
        row.process,
        '${row.quantity}',
        Money.formatCents(row.cents),
      ]));
    }
    return buffer.toString();
  }

  String fileName(String prefix) {
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return '$prefix-$stamp.csv';
  }
}
