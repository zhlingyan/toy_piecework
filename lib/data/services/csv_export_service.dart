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
  String settlementCsv(SettlementResult result) {
    final buffer = StringBuffer(bom);
    buffer.write(_row([
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
    ]));
    for (final worker in result.workers) {
      // 加班单独列出来，方便核对「这个月加了多少班、多拿了多少」
      final overtimeQuantity = worker.groups
          .where((group) => group.overtime)
          .fold(0, (sum, group) => sum + group.quantity);
      final overtimeCents = worker.groups
          .where((group) => group.overtime)
          .fold(0, (sum, group) => sum + group.subtotalCents);
      buffer.write(_row([
        worker.workerCode,
        worker.workerName,
        Money.formatCents(worker.pieceCents),
        Money.formatCents(worker.bonusCents),
        Money.formatCents(worker.hourlyCents),
        Money.formatCents(worker.deductionCents),
        Money.formatCents(worker.advanceCents),
        Money.formatCents(worker.netCents),
        '$overtimeQuantity',
        Money.formatCents(overtimeCents),
        worker.isArchived ? '已停用档案' : '',
        worker.settlementStatus.label,
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
      '${result.range.label}，逐笔取整后合计',
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
