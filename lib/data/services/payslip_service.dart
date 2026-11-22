import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/adjustment.dart';
import '../models/settlement.dart';

/// 单人电子工资条长图。
///
/// 直接用 Canvas 绘制而不是截图 Widget：
/// * 不依赖页面布局，后台也能生成；
/// * 明细过长时按行数分页，逐页 `toImage`，内存占用恒定，长账不会 OOM。
class PayslipService {
  const PayslipService();

  static const double _width = 1080;
  static const double _margin = 48;
  static const double _rowHeight = 86;
  static const double _tableHeaderHeight = 58;

  /// 生成工资条图片（可能多张）。
  Future<List<Uint8List>> buildPayslip({
    required WorkerSettlement worker,
    required DateRange range,
    required List<Adjustment> adjustments,
    String factoryName = '玩具厂计件工资条',
  }) async {
    final rows = <_PayslipRow>[
      for (final group in worker.groups) _PayslipRow.piece(group),
      for (final adjustment in adjustments) _PayslipRow.adjustment(adjustment),
    ];

    final pages = _paginate(rows);
    final images = <Uint8List>[];
    for (var index = 0; index < pages.length; index++) {
      final isLast = index == pages.length - 1;
      final bytes = await _paintPage(
        factoryName: factoryName,
        worker: worker,
        range: range,
        rows: pages[index],
        pageIndex: index,
        pageCount: pages.length,
        showTotals: isLast,
      );
      images.add(bytes);
    }
    return images;
  }

  static const int _maxRowsPerPage = 18;

  /// 每页行数切分：每页不超过 18 行，且**均分**而不是「前满后空」。
  ///
  /// 均分是为了避免出现只有三四行的孤页——比如 36 行若按 18/18 切没问题，
  /// 但 22 行按「先填满」会切出 18 + 4，末页只剩 4 行还硬塞一块合计区，很难看。
  /// 因此先按上限算出最少页数，再把行数平均摊到各页。
  ///
  /// 单页渲染 + 逐页 `toImage` 是控制内存的关键——
  /// 一张 200 行的工资条若整体截图，很容易在低端机上 OOM。
  static List<int> pageSizes(int rowCount) {
    if (rowCount <= 0) return const [0];
    if (rowCount <= _maxRowsPerPage) return [rowCount];
    final pages = (rowCount / _maxRowsPerPage).ceil();
    final base = rowCount ~/ pages;
    final extra = rowCount % pages;
    return [
      for (var index = 0; index < pages; index++)
        index < extra ? base + 1 : base,
    ];
  }

  List<List<_PayslipRow>> _paginate(List<_PayslipRow> rows) {
    final pages = <List<_PayslipRow>>[];
    var index = 0;
    for (final size in pageSizes(rows.length)) {
      pages.add(rows.sublist(index, index + size));
      index += size;
    }
    return pages;
  }

  Future<Uint8List> _paintPage({
    required String factoryName,
    required WorkerSettlement worker,
    required DateRange range,
    required List<_PayslipRow> rows,
    required int pageIndex,
    required int pageCount,
    required bool showTotals,
  }) async {
    final isFirst = pageIndex == 0;
    final headerHeight = isFirst ? 236.0 : 128.0;
    final totalsHeight = showTotals ? 356.0 : 0.0;
    final height = headerHeight +
        _tableHeaderHeight +
        rows.length * _rowHeight +
        totalsHeight +
        96;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final pageRect = Rect.fromLTWH(0, 0, _width, height);

    // 背景
    canvas.drawRect(pageRect, Paint()..color = const Color(0xFFFFFFFF));

    var y = 0.0;
    if (isFirst) {
      y = _drawFirstHeader(canvas, factoryName, worker, range);
    } else {
      y = _drawContinuationHeader(canvas, worker, range, pageIndex, pageCount);
    }

    // 表头
    _drawText(
      canvas,
      '项目',
      Offset(_margin, y + 16),
      fontSize: 26,
      color: const Color(0xFF5B6472),
      weight: FontWeight.w600,
    );
    _drawText(
      canvas,
      '数量 / 单价',
      Offset(_margin + 380, y + 16),
      fontSize: 26,
      color: const Color(0xFF5B6472),
      weight: FontWeight.w600,
    );
    _drawText(
      canvas,
      '金额(元)',
      Offset(_width - _margin - 220, y + 16),
      fontSize: 26,
      color: const Color(0xFF5B6472),
      weight: FontWeight.w600,
      maxWidth: 220,
      align: TextAlign.right,
    );
    y += _tableHeaderHeight;
    canvas.drawLine(
      Offset(_margin, y - 10),
      Offset(_width - _margin, y - 10),
      Paint()
        ..color = const Color(0xFFE6E9EF)
        ..strokeWidth = 2,
    );

    if (rows.isEmpty) {
      _drawText(
        canvas,
        '本区间没有计件与调整项',
        Offset(_margin, y + 24),
        fontSize: 28,
        color: const Color(0xFF98A2B3),
      );
      y += _rowHeight;
    }

    for (final row in rows) {
      _drawRow(canvas, row, y);
      y += _rowHeight;
      canvas.drawLine(
        Offset(_margin, y - 6),
        Offset(_width - _margin, y - 6),
        Paint()
          ..color = const Color(0xFFF0F2F5)
          ..strokeWidth = 1.4,
      );
    }

    if (showTotals) {
      _drawTotals(canvas, worker, y + 12);
    }

    // 页脚
    _drawText(
      canvas,
      '${Dates.ymd(DateTime.now())} 生成 · 逐笔取整后合计',
      Offset(_margin, height - 62),
      fontSize: 22,
      color: const Color(0xFF98A2B3),
    );
    _drawText(
      canvas,
      '第 ${pageIndex + 1} / $pageCount 页',
      Offset(_width - _margin - 180, height - 62),
      fontSize: 22,
      color: const Color(0xFF98A2B3),
      maxWidth: 180,
      align: TextAlign.right,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  double _drawFirstHeader(
    Canvas canvas,
    String factoryName,
    WorkerSettlement worker,
    DateRange range,
  ) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _width, 8),
      Paint()..color = const Color(0xFF14549B),
    );
    _drawText(
      canvas,
      factoryName,
      Offset(_margin, 44),
      fontSize: 30,
      color: const Color(0xFF5B6472),
      weight: FontWeight.w600,
    );
    _drawText(
      canvas,
      '工资条',
      Offset(_margin, 86),
      fontSize: 52,
      color: const Color(0xFF14549B),
      weight: FontWeight.w800,
    );
    _drawText(
      canvas,
      '${worker.workerName}${worker.workerCode.isEmpty ? '' : '（${worker.workerCode}）'}',
      Offset(_margin, 160),
      fontSize: 36,
      color: const Color(0xFF1B2430),
      weight: FontWeight.w700,
    );
    _drawText(
      canvas,
      '结算区间 ${range.label}',
      Offset(_width - _margin - 420, 168),
      fontSize: 26,
      color: const Color(0xFF5B6472),
      maxWidth: 420,
      align: TextAlign.right,
    );
    return 236;
  }

  double _drawContinuationHeader(
    Canvas canvas,
    WorkerSettlement worker,
    DateRange range,
    int pageIndex,
    int pageCount,
  ) {
    _drawText(
      canvas,
      '${worker.workerName} · 工资条（续）',
      Offset(_margin, 40),
      fontSize: 34,
      color: const Color(0xFF14549B),
      weight: FontWeight.w700,
    );
    _drawText(
      canvas,
      range.label,
      Offset(_margin, 86),
      fontSize: 24,
      color: const Color(0xFF5B6472),
    );
    canvas.drawLine(
      Offset(_margin, 118),
      Offset(_width - _margin, 118),
      Paint()
        ..color = const Color(0xFFE6E9EF)
        ..strokeWidth = 2,
    );
    return 128;
  }

  void _drawRow(Canvas canvas, _PayslipRow row, double y) {
    _drawText(
      canvas,
      row.title,
      Offset(_margin, y + 14),
      fontSize: 30,
      color: const Color(0xFF1B2430),
      weight: FontWeight.w600,
      maxWidth: 360,
    );
    _drawText(
      canvas,
      row.subtitle,
      Offset(_margin + 380, y + 20),
      fontSize: 24,
      color: const Color(0xFF5B6472),
      maxWidth: 300,
    );
    _drawText(
      canvas,
      row.amount,
      Offset(_width - _margin - 220, y + 14),
      fontSize: 30,
      color: row.amountColor,
      weight: FontWeight.w700,
      maxWidth: 220,
      align: TextAlign.right,
    );
  }

  void _drawTotals(Canvas canvas, WorkerSettlement worker, double y) {
    const left = _margin;
    final right = _width - _margin;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, y, right, y + 300),
        const Radius.circular(20),
      ),
      Paint()..color = const Color(0xFFF5F7FA),
    );

    var cursor = y + 22;
    void line(String label, String value, {Color? color, bool bold = false}) {
      _drawText(
        canvas,
        label,
        Offset(left + 28, cursor),
        fontSize: bold ? 30 : 26,
        color: const Color(0xFF5B6472),
        weight: bold ? FontWeight.w700 : FontWeight.w400,
      );
      _drawText(
        canvas,
        value,
        Offset(right - 28 - 240, cursor),
        fontSize: bold ? 34 : 26,
        color: color ?? const Color(0xFF1B2430),
        weight: bold ? FontWeight.w800 : FontWeight.w600,
        maxWidth: 240,
        align: TextAlign.right,
      );
      cursor += bold ? 52 : 38;
    }

    line('计件工资', Money.formatCents(worker.pieceCents));
    line('补贴', '+${Money.formatCents(worker.bonusCents)}');
    line('计时', '+${Money.formatCents(worker.hourlyCents)}');
    line('扣款', '-${Money.formatCents(worker.deductionCents)}');
    line('预支', '-${Money.formatCents(worker.advanceCents)}');

    canvas.drawLine(
      Offset(left + 28, cursor - 6),
      Offset(right - 28, cursor - 6),
      Paint()
        ..color = const Color(0xFFD9DEE7)
        ..strokeWidth = 1.6,
    );
    cursor += 8;
    line(
      '本期应付',
      '${Money.formatCents(worker.netCents)} 元',
      color: worker.isNegative ? const Color(0xFFC62828) : const Color(0xFF14549B),
      bold: true,
    );
    if (worker.isNegative) {
      _drawText(
        canvas,
        '应付为负数，请核对扣款与预支',
        Offset(left + 28, cursor),
        fontSize: 22,
        color: const Color(0xFFC62828),
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double maxWidth = 640,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          height: 1.35,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
    painter.dispose();
  }
}

class _PayslipRow {
  const _PayslipRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
  });

  factory _PayslipRow.piece(PieceGroup group) {
    return _PayslipRow(
      title: '${group.toyName}'
          '${group.process == Defaults.defaultProcess ? '' : ' / ${group.process}'}',
      subtitle: '${group.quantity} 件 × ${Money.formatPrice(group.unitPriceTenThousandth)}',
      amount: Money.formatCents(group.subtotalCents),
      amountColor: const Color(0xFF1B2430),
    );
  }

  factory _PayslipRow.adjustment(Adjustment adjustment) {
    final positive = adjustment.type.sign > 0;
    return _PayslipRow(
      title: '${adjustment.type.label} · ${adjustment.remark}',
      subtitle: adjustment.date,
      amount: Money.formatCentsSigned(adjustment.signedCents),
      amountColor: positive ? const Color(0xFF1B7F3B) : const Color(0xFFC62828),
    );
  }

  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
}
