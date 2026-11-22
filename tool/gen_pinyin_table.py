"""生成 lib/domain/pinyin/pinyin_table.dart（零依赖离线首字母表）。

用法：python tool/gen_pinyin_table.py
依赖：pip install pypinyin（仅生成期使用，运行期零依赖）
"""
import io
import os
from pypinyin import pinyin, Style

START = 0x4E00
END = 0x9FFF  # CJK 统一表意文字基本区

groups = {chr(ord('A') + i): [] for i in range(26)}

for code in range(START, END + 1):
    ch = chr(code)
    try:
        result = pinyin(ch, style=Style.FIRST_LETTER, errors='ignore')
    except Exception:
        continue
    if not result or not result[0]:
        continue
    letter = result[0][0].upper()
    if letter not in groups:
        continue
    groups[letter].append(ch)

lines = []
lines.append('// 由 tool/gen_pinyin_table.py 自动生成，请勿手工修改。')
lines.append('//')
lines.append('// 覆盖 CJK 基本区常用汉字的首字母映射，运行期零依赖、零网络。')
lines.append('// 构建方式：把每个字母下的汉字拼成一个长字符串，首次使用时懒加载为 Map。')
lines.append('')
lines.append('const Map<String, String> kInitialCharTable = {')

total = 0
for letter in sorted(groups):
    chars = ''.join(groups[letter])
    total += len(chars)
    lines.append("  '%s': '%s'," % (letter, chars))
lines.append('};')
lines.append('')

target = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'lib', 'domain', 'pinyin', 'pinyin_table.dart',
)
os.makedirs(os.path.dirname(target), exist_ok=True)
with io.open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(lines))

print('chars=%d file=%s size=%dKB' % (total, target, os.path.getsize(target) / 1024))
