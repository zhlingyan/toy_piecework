import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/clock.dart';
import 'package:toy_piecework/core/dates.dart';
import 'package:toy_piecework/data/services/csv_export_service.dart';

import 'support/fixture.dart';

/// 打印总表隔离：只输出正式汇总字段，审计信息一律过滤。
void main() {
  const csv = CsvExportService();

  test('总表白名单固定 12 列，与审计字段集合无交集', () {
    expect(CsvExportService.settlementPrintColumns.length, 12);
    expect(CsvExportService.settlementPrintColumns.first, '工人编号');
    expect(CsvExportService.settlementPrintColumns.last, '结算状态');
    for (final field in CsvExportService.auditOnlyFields) {
      expect(CsvExportService.settlementPrintColumns.contains(field), isFalse);
    }
  });

  test('审计文本清洗：时间戳 / 取消理由 / 变更历史 / 追加标识全部剔除', () {
    const raw = '结算于 2026-11-22 09:30:05 · 取消理由：金额算错，重结 · '
        '#2 取消结算 · 变更历史：第 2 次';
    final clean = CsvExportService.stripAuditMetadata(raw);
    expect(clean.contains('2026-11-22 09:30:05'), isFalse);
    expect(clean.contains('取消理由'), isFalse);
    expect(clean.contains('金额算错'), isFalse);
    expect(clean.contains('变更历史'), isFalse);
    expect(clean.contains('#2'), isFalse);
    expect(clean.contains('第 2 次'), isFalse);
    // 正常文字不受影响
    expect(CsvExportService.stripAuditMetadata('已停用档案'), '已停用档案');
    expect(CsvExportService.stripAuditMetadata('未结算'), '未结算');
  });

  test('账本有完整变更历史，导出的总表仍不含任何审计信息', () async {
    AppClock.override(() => DateTime(2026, 11, 22, 9, 30, 5));
    final f = await Fixture.create();
    addTearDown(() async {
      AppClock.reset();
      await f.dispose();
    });
    final nov = DateRange.of('2026-11-01', '2026-11-30');
    final worker = await f.addWorker('张三', code: 'W001');
    final toy = await f.addToy('小熊', priceTenThousandth: 2000);
    await f.records.create(
      date: '2026-11-05',
      worker: worker,
      toy: toy,
      quantity: 100,
      remark: '含逗号,正常备注',
    );
    await f.settlementEntries.markRange(
      workerId: worker.id,
      months: const ['2026-11'],
      range: nov,
      settled: true,
    );
    await f.settlementEntries.markRange(
      workerId: worker.id,
      months: const ['2026-11'],
      range: nov,
      settled: false,
      reason: '金额算错，重结',
    );
    expect(await f.settlementHistory.countForWorker(worker.id), 2);

    final text = csv.settlementCsv(await f.settlements.settle(nov));
    // 正式信息仍在
    expect(text, contains('结算状态'));
    expect(text, contains('张三'));
    expect(text, contains('20.00'));
    // 审计信息一个都不出现
    expect(text.contains('取消理由'), isFalse);
    expect(text.contains('变更历史'), isFalse);
    expect(text.contains('金额算错，重结'), isFalse);
    expect(text.contains('2026-11-22 09:30:05'), isFalse);
    expect(
      RegExp(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}').hasMatch(text),
      isFalse,
    );
    expect(text.split(CsvExportService.lineEnding).first,
        '${CsvExportService.bom}${CsvExportService.settlementPrintColumns.join(',')}');
  });
}
