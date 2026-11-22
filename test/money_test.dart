import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/core/money.dart';

void main() {
  group('单笔小计取整（验收用例 1）', () {
    test('0.035 元 × 100 件 = 3.50 元', () {
      expect(
        Money.subtotalCents(quantity: 100, priceTenThousandth: 350),
        350,
      );
      expect(Money.formatCents(350), '3.50');
    });

    test('0.20 元与 0.25 元各 100 件，逐笔取整后合计 45.00 元', () {
      final first = Money.subtotalCents(quantity: 100, priceTenThousandth: 2000);
      final second = Money.subtotalCents(quantity: 100, priceTenThousandth: 2500);
      expect(first, 2000); // 20.00
      expect(second, 2500); // 25.00
      expect(Money.formatCents(first + second), '45.00');
    });

    test('三分之一分的情况按四舍五入到分', () {
      // 1 件 × 0.035 元 = 3.5 分 => 4 分
      expect(Money.subtotalCents(quantity: 1, priceTenThousandth: 350), 4);
      // 3 件 × 0.035 元 = 10.5 分 => 11 分
      expect(Money.subtotalCents(quantity: 3, priceTenThousandth: 350), 11);
      // 2 件 × 0.035 元 = 7 分，无小数
      expect(Money.subtotalCents(quantity: 2, priceTenThousandth: 350), 7);
    });

    test('大数量不溢出（10 万件 × 1.2345 元）', () {
      expect(
        Money.subtotalCents(quantity: 100000, priceTenThousandth: 12345),
        12345000,
      );
      expect(Money.formatCents(12345000), '123450.00');
    });
  });

  group('单价解析', () {
    test('四位小数精确解析，不经过浮点', () {
      expect(Money.tryParsePrice('0.035'), 350);
      expect(Money.tryParsePrice('0.2'), 2000);
      expect(Money.tryParsePrice('1.2345'), 12345);
      expect(Money.tryParsePrice('12'), 120000);
    });

    test('超过四位小数按第 5 位四舍五入', () {
      expect(Money.tryParsePrice('0.03599'), 360);
      expect(Money.tryParsePrice('0.00004'), 0);
      expect(Money.tryParsePrice('0.00005'), 1);
    });

    test('全角数字与中文小数点可识别', () {
      expect(Money.tryParsePrice('０．０３５'), 350);
      expect(Money.tryParsePrice('1。5'), 15000);
    });

    test('非法输入返回 null', () {
      expect(Money.tryParsePrice(''), isNull);
      expect(Money.tryParsePrice('abc'), isNull);
      expect(Money.tryParsePrice('1.2.3'), isNull);
      expect(Money.tryParsePrice('.'), isNull);
    });
  });

  group('金额解析（调整项）', () {
    test('两位小数', () {
      expect(Money.tryParseCents('20'), 2000);
      expect(Money.tryParseCents('0.05'), 5);
      expect(Money.tryParseCents('15.5'), 1550);
    });

    test('负数不被吞掉（用于校验提示）', () {
      expect(Money.tryParseCents('-5'), -500);
    });
  });

  group('展示格式', () {
    test('金额固定两位小数，负数保留符号', () {
      expect(Money.formatCents(0), '0.00');
      expect(Money.formatCents(4500), '45.00');
      expect(Money.formatCents(5), '0.05');
      expect(Money.formatCents(-500), '-5.00');
    });

    test('单价按实际精度展示，至少两位小数', () {
      expect(Money.formatPrice(350), '0.035');
      expect(Money.formatPrice(2000), '0.20');
      expect(Money.formatPrice(2500), '0.25');
      expect(Money.formatPrice(12345), '1.2345');
      expect(Money.formatPrice(10000), '1.00');
      expect(Money.formatPrice(0), '0.00');
    });

    test('带符号金额', () {
      expect(Money.formatCentsSigned(2000), '+20.00');
      expect(Money.formatCentsSigned(-500), '-5.00');
    });
  });
}
