import 'package:flutter_test/flutter_test.dart';
import 'package:toy_piecework/domain/pinyin/pinyin_helper.dart';

void main() {
  group('首字母提取', () {
    test('普通姓名', () {
      expect(PinyinHelper.initialsOf('张三'), 'ZS');
      expect(PinyinHelper.initialsOf('李四'), 'LS');
      expect(PinyinHelper.initialsOf('王小二'), 'WXE');
    });

    test('多音姓氏优先映射（含验收要求 6 例）', () {
      expect(PinyinHelper.initialsOf('单田芳'), startsWith('S'));
      expect(PinyinHelper.initialsOf('曾志伟'), startsWith('Z'));
      expect(PinyinHelper.initialsOf('解晓东'), startsWith('X'));
      expect(PinyinHelper.initialsOf('查良镛'), startsWith('Z'));
      expect(PinyinHelper.initialsOf('仇英'), startsWith('Q'));
      expect(PinyinHelper.initialsOf('区家豪'), startsWith('O'));
    });

    test('非首字不套用姓氏读音', () {
      // 第二个「单」按常用读音 D
      expect(PinyinHelper.initialsOf('王单一'), 'WDY');
    });

    test('玩具与工序名', () {
      expect(PinyinHelper.initialsOf('小熊'), 'XX');
      expect(PinyinHelper.initialsOf('积木/整件'), 'JMZJ');
    });

    test('英文数字混合', () {
      expect(PinyinHelper.initialsOf('ABC小熊'), 'ABCXX');
      expect(PinyinHelper.initialsOf('2号车间'), '2HCJ');
    });

    test('空值与空白', () {
      expect(PinyinHelper.initialsOf(''), '');
      expect(PinyinHelper.initialsOf('   '), '');
    });
  });

  group('分组', () {
    test('A–Z 归组，数字归 #', () {
      expect(PinyinHelper.groupKey('ZS'), 'Z');
      expect(PinyinHelper.groupKey('2HCJ'), '#');
      expect(PinyinHelper.groupKey(''), '#');
    });

    test('按首字母分组，# 排最后', () {
      final names = ['张三', '李四', '2号', '安琪', '曾志伟'];
      final grouped = PinyinHelper.groupByInitial<String>(
        names,
        initialsOf: (n) => PinyinHelper.initialsOf(n),
        codeOf: (_) => '',
        nameOf: (n) => n,
      );
      expect(grouped.keys.toList(), ['A', 'L', 'Z', '#']);
      expect(grouped['Z']!.contains('曾志伟'), isTrue);
    });
  });

  group('混合搜索', () {
    test('中文、首字母、编号都能命中', () {
      expect(
        PinyinHelper.matches(query: '张', name: '张三', initials: 'ZS', code: 'W001'),
        isTrue,
      );
      expect(
        PinyinHelper.matches(query: 'zs', name: '张三', initials: 'ZS', code: 'W001'),
        isTrue,
      );
      expect(
        PinyinHelper.matches(query: 'w00', name: '张三', initials: 'ZS', code: 'W001'),
        isTrue,
      );
      expect(
        PinyinHelper.matches(query: '李', name: '张三', initials: 'ZS', code: 'W001'),
        isFalse,
      );
    });

    test('首字母前缀匹配，不做中间匹配（避免误命中）', () {
      expect(
        PinyinHelper.matches(query: 'S', name: '张三', initials: 'ZS'),
        isFalse,
      );
      expect(
        PinyinHelper.matches(query: 'Z', name: '张三', initials: 'ZS'),
        isTrue,
      );
    });
  });
}
