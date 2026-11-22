import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/constants.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/services/csv_export_service.dart';
import 'package:toy_piecework/data/services/payslip_service.dart';

import 'support/fixture.dart';

void main() {
  late Fixture f;
  const csv = CsvExportService();

  setUp(() async {
    f = await Fixture.create();
  });

  tearDown(() async {
    await f.dispose();
  });

  group('CSV 导出', () {
    test('带 UTF-8 BOM、CRLF 换行，Excel 打开不乱码', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 350); // 0.035
      await f.records.create(
        date: '2026-06-01',
        worker: worker,
        toy: toy,
        quantity: 100,
        remark: '含逗号,与"引号"',
      );

      final records = await f.records.listRange(
        DateRange.of('2026-06-01', '2026-06-30'),
      );
      final text = csv.recordsCsv(records);

      expect(text.startsWith(CsvExportService.bom), isTrue);
      expect(text.contains('\r\n'), isTrue);
      final lines = text.split('\r\n');
      expect(lines.first, '${CsvExportService.bom}日期,工人,玩具,工序,单价(元),数量,小计(元),备注');
      expect(lines[1], contains('2026-06-01,张三,小熊,整件,0.035,100,3.50,'));
      // 含逗号与引号的字段整体加引号，内部引号翻倍
      expect(lines[1], contains('"含逗号,与""引号"""'));
    });

    test('结算表：一人一行 + 合计行', () async {
      final worker = await f.addWorker('张三');
      final toy = await f.addToy('小熊', priceTenThousandth: 2000);
      await f.records.create(
        date: '2026-06-01',
        worker: worker,
        toy: toy,
        quantity: 500,
      );
      await f.adjustments.create(
        date: '2026-06-01',
        worker: worker,
        type: AdjustmentType.bonus,
        amountCents: 2000,
        remark: '全勤',
      );

      final result = await f.settlements.settle(
        DateRange.of('2026-06-01', '2026-06-30'),
      );
      final text = csv.settlementCsv(result);
      // 末尾本来就有一个 CRLF，split 后要去掉那个空串
      final lines = text.split('\r\n').where((line) => line.isNotEmpty).toList();

      expect(lines.length, 3, reason: '表头 + 1 行明细 + 合计');
      expect(lines.first, contains('结算状态'));
      expect(lines[1], contains('100.00,20.00,0.00,0.00,0.00,120.00'));
      expect(lines[1], endsWith('未结算'));
      expect(lines[2], startsWith(',合计,100.00,20.00'));
      expect(lines[2], contains('逐笔取整后合计'));
      expect(lines[2], contains('未结 120.00'));
    });

    test('字段转义：换行与纯文本原样保留', () {
      expect(CsvExportService.escape('普通'), '普通');
      expect(CsvExportService.escape('a,b'), '"a,b"');
      expect(CsvExportService.escape('a\nb'), '"a\nb"');
      expect(CsvExportService.escape('a"b'), '"a""b"');
    });
  });

  group('工资条分页', () {
    test('不超过一页上限时只有一页', () {
      expect(PayslipService.pageSizes(0), [0]);
      expect(PayslipService.pageSizes(1), [1]);
      expect(PayslipService.pageSizes(14), [14]);
      expect(PayslipService.pageSizes(18), [18]);
    });

    test('多页时均分，每页不超过 18 行，不出现孤页', () {
      expect(PayslipService.pageSizes(19), [10, 9]);
      expect(PayslipService.pageSizes(32), [16, 16]);
      expect(PayslipService.pageSizes(36), [18, 18]);
      expect(PayslipService.pageSizes(37), [13, 12, 12]);

      const twoHundred = 200;
      final sizes = PayslipService.pageSizes(twoHundred);
      expect(sizes.fold(0, (sum, size) => sum + size), twoHundred);
      for (final size in sizes) {
        expect(size, lessThanOrEqualTo(18));
        expect(size, greaterThanOrEqualTo(14), reason: '不允许出现孤页');
      }
    });
  });
}
