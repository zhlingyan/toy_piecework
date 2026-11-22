# 玩具厂计件计数与工资结算（Android 管理员版）

车间统计员一个人用的**单机记账 App**：记件数、算工资、锁账、发工资条。
**离线优先**——记账、查询、结算全程不联网；云端备份只是可选的异地留档。

- 技术栈：Flutter 3.50 / Dart 3.14，本地 SQLite（`sqflite`）
- 目标平台：Android 7.0+（minSdk 24），单 APK 直接安装
- 金额精度：单价按「万分之一元」整数存储，小计按「分」整数存储，**逐笔四舍五入后累加**
- 测试：85 条自动化测试（核心金额/锁账/回收站/备份/导入逻辑 + 界面冒烟）

---

## 一、快速开始

```bash
# 依赖
flutter pub get

# 静态检查 + 测试
flutter analyze
flutter test

# 出包（签名配置见 docs/签名密钥备份说明.md）
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

使用说明见 [docs/操作手册.md](docs/操作手册.md)。

---

## 二、目录结构

```
lib/
├── core/                  基础设施（无业务依赖）
│   ├── constants.dart     表名、调整项类型、阈值、默认值
│   ├── money.dart         金额整数运算：万分之一元 / 分 / 半进位取整
│   ├── dates.dart         日期与区间（含首尾、拒绝 2026-02-30）
│   ├── failures.dart      可直出中文提示的业务异常
│   ├── clock.dart         可注入时钟（测试用）
│   └── id_gen.dart        UUID 生成（防重复提交的关键）
├── data/
│   ├── db/                建表语句 + 打开/事务封装
│   ├── models/            不可变模型（Worker/Toy/PieceRecord/Adjustment/结算聚合）
│   ├── repositories/      5 张表的读写，全部写入走事务
│   └── services/          跨表能力：备份、旧账导入、CSV、工资条、报表、云备份
├── domain/
│   ├── rules/             锁账校验、回收站窗口
│   └── pinyin/            离线拼音首字母表 + 多音姓氏兜底
├── services/              应用级容器：AppServices、设置、文件出入
├── state/                 跨页选中状态（按 id，不用下标）
└── ui/                    概览 / 计数 / 结算 / 设置 / 档案 / 报表 / 回收站
```

---

## 三、关键设计决策

### 1. 金额为什么全用整数

浮点数 `0.035 * 100` 可能得到 `3.4999999999999996`，四舍五入到分就会出错。
本项目：

- 单价存 `unit_price_ten_thousandth`（0.035 元 → `350`）
- 小计存 `subtotal_cents`（元 × 100 的整数）
- 每笔 `round(quantity × price / 100)`，**先取整到分再累加**，报表脚注「逐笔取整后合计」

### 2. 快照优先，改档案不影响历史

`piece_records` 存 `worker_name_snapshot / toy_name_snapshot / process_snapshot /
unit_price_snapshot`。档案改名、调价、停用都不会改写任何历史单据。

改数量时沿用**原单价快照**重算；只改备注则金额完全不动。

### 3. 分组键含单价，杜绝「平均单价」

结算按 `(worker_id, toy_id, process_snapshot, unit_price_snapshot)` 分组。
同一工序中途调价（0.20 做 100 件 + 0.25 做 100 件）必然拆成两行，合计 45.00。

### 4. 防重复提交落在数据库层

保存前先生成 UUID 作为主键，插入时用 `ConflictAlgorithm.ignore`；
双击只会落一行，第二次插入返回已存在的记录。

### 5. 锁账只有一个闸门

所有写操作（新增/修改/删除/回收站恢复）统一走
`MonthLockGuard.assertEditable / assertRangeEditable`。
改日期跨月时**同时校验原月份与目标月份**。

### 6. 只有调整项的工人也要出现

结算先用 SQL 分别聚合计件与调整项，再在 Dart 里按 `worker_id` 合并，
因此「只领补贴、没有计件」的人不会从结算清单里漏掉。

### 7. 工资条用 Canvas 画，不用截图

1080px 宽的工资条逐页 `Picture.toImage` 生成 PNG，每页按行数均分（每页 ≤18 行）。
一张几百行的工资条整体截图会 OOM，分页渲染把内存占用压成常数。

### 8. 云备份只在前台触发

应用启动/回到前台时检查一次：距上次成功 ≥24 小时**且**本地确有新写入
（`MAX(updated_at)` 晚于上次备份时间）才上传。不用后台定时器——
Android 会杀后台任务，定时器既不可靠又费电。云端只保留最近 30 份**自动**备份，
手动备份永不自动清理。

---

## 四、验收用例（已自动化覆盖）

| 用例 | 覆盖位置 |
| --- | --- |
| 100×0.20 + 100×0.25 = 45.00；0.035×100 = 3.50 | `test/settlement_test.dart`、`test/money_test.dart` |
| 新增档案不串位；双击只存一笔；超量/超金额二次确认 | `test/app_smoke_test.dart`、`test/piece_record_test.dart` |
| 100+20+10−5−15 = 110.00；只有调整项的工人可见 | `test/settlement_test.dart` |
| 锁账拦截写与恢复；跨月双向校验；>30 天不可恢复 | `test/lock_test.dart`、`test/trash_test.dart` |
| 旧账重复导入加 0；损坏 JSON 不覆盖原账；云盘离线不影响本地 | `test/legacy_import_test.dart`、`test/backup_test.dart` |
| CSV 带 BOM；工资条分页不出现孤页 | `test/csv_payslip_test.dart` |

---

## 五、数据与隐私

- 全部数据在手机本地 SQLite，不上传、不埋点、不采集设备信息；
- WebDAV 账号与应用密码存在系统安全存储（Android Keystore 加密），
  不写进账本与备份文件；
- 备份 JSON 是**明文**，包含工人的姓名与工资，请自行保管好备份文件。

---

## 六、升级与备份

- 覆盖安装即可升级，账本不丢（前提：同一个签名证书）；
- 升级前建议 `设置 → 导出本地备份`；
- 卸载会清空应用数据；
- 密钥文件与密码见 [docs/签名密钥备份说明.md](docs/签名密钥备份说明.md)。
