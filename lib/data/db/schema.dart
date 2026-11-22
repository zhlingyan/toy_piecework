import '../../core/constants.dart';

/// 数据库结构定义（版本 4）。
///
/// 索引原则：日期、工人、删除标记三条高频过滤路径全部建索引。
/// 不启用外键约束——历史流水必须能在档案归档后继续存在，
/// 引用完整性由仓储层保证（插入前自动补建缺失档案）。
class Schema {
  Schema._();

  static const int version = 4;

  static const List<String> createStatements = [
    '''
    CREATE TABLE ${Tables.workers} (
      id TEXT PRIMARY KEY NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      id_card TEXT NOT NULL DEFAULT '',
      pinyin_initials TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE ${Tables.toys} (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      process TEXT NOT NULL DEFAULT '${Defaults.defaultProcess}',
      unit_price_ten_thousandth INTEGER NOT NULL DEFAULT 0,
      overtime_price_ten_thousandth INTEGER NOT NULL DEFAULT 0,
      pinyin_initials TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE ${Tables.pieceRecords} (
      id TEXT PRIMARY KEY NOT NULL,
      date TEXT NOT NULL,
      minute_of_day INTEGER NOT NULL DEFAULT 0,
      worker_id TEXT NOT NULL,
      toy_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      toy_name_snapshot TEXT NOT NULL,
      process_snapshot TEXT NOT NULL,
      unit_price_snapshot INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      subtotal_cents INTEGER NOT NULL,
      overtime INTEGER NOT NULL DEFAULT 0,
      overtime_price_snapshot INTEGER NOT NULL DEFAULT 0,
      overtime_multiplier INTEGER NOT NULL DEFAULT 1000,
      remark TEXT NOT NULL DEFAULT '',
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (quantity > 0)
    )
    ''',
    '''
    CREATE TABLE ${Tables.adjustments} (
      id TEXT PRIMARY KEY NOT NULL,
      date TEXT NOT NULL,
      minute_of_day INTEGER NOT NULL DEFAULT 0,
      worker_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      work_minutes INTEGER NOT NULL DEFAULT 0,
      hourly_rate_cents INTEGER NOT NULL DEFAULT 0,
      remark TEXT NOT NULL,
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (amount_cents > 0),
      CHECK (work_minutes >= 0),
      CHECK (hourly_rate_cents >= 0),
      CHECK (type IN ('bonus','hourly','deduction','advance'))
    )
    ''',
    '''
    CREATE TABLE ${Tables.processPresets} (
      name TEXT PRIMARY KEY NOT NULL,
      is_builtin INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE ${Tables.lockedMonths} (
      month TEXT PRIMARY KEY NOT NULL,
      is_locked INTEGER NOT NULL DEFAULT 0,
      locked_at INTEGER,
      unlocked_at INTEGER
    )
    ''',
    // 结算状态：按「工人 + 月份」记。锁账管「能不能改」，这张表管「钱发没发」，
    // 两者刻意解耦：可以先结算不锁账，也可以先锁账再回头标记已结算。
    '''
    CREATE TABLE ${Tables.settlementMarks} (
      worker_id TEXT NOT NULL,
      month TEXT NOT NULL,
      is_settled INTEGER NOT NULL DEFAULT 0,
      settled_at INTEGER,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (worker_id, month)
    )
    ''',
    // ---- 索引 ----
    'CREATE INDEX idx_workers_archived ON ${Tables.workers}(is_archived)',
    'CREATE INDEX idx_workers_code ON ${Tables.workers}(code)',
    'CREATE INDEX idx_toys_archived ON ${Tables.toys}(is_archived)',
    'CREATE INDEX idx_toys_name_process ON ${Tables.toys}(name, process)',
    'CREATE INDEX idx_records_date ON ${Tables.pieceRecords}(date)',
    'CREATE INDEX idx_records_date_minute ON ${Tables.pieceRecords}(date, minute_of_day)',
    'CREATE INDEX idx_records_worker_date ON ${Tables.pieceRecords}(worker_id, date)',
    'CREATE INDEX idx_records_toy_date ON ${Tables.pieceRecords}(toy_id, date)',
    'CREATE INDEX idx_records_deleted ON ${Tables.pieceRecords}(deleted_at)',
    'CREATE INDEX idx_adjustments_date ON ${Tables.adjustments}(date)',
    'CREATE INDEX idx_adjustments_worker_date ON ${Tables.adjustments}(worker_id, date)',
    'CREATE INDEX idx_adjustments_deleted ON ${Tables.adjustments}(deleted_at)',
    'CREATE INDEX idx_settlement_month ON ${Tables.settlementMarks}(month)',
  ];

  /// 恢复/导入前清空用，顺序无关（无外键）。
  static const List<String> clearStatements = [
    'DELETE FROM ${Tables.pieceRecords}',
    'DELETE FROM ${Tables.adjustments}',
    'DELETE FROM ${Tables.toys}',
    'DELETE FROM ${Tables.workers}',
    'DELETE FROM ${Tables.lockedMonths}',
    'DELETE FROM ${Tables.processPresets}',
    'DELETE FROM ${Tables.settlementMarks}',
  ];

  /// 预置常用工序。
  ///
  /// 用 `INSERT OR IGNORE` 而不是 `INSERT`：建库、升级、恢复三条路径都会跑它，
  /// 重复执行必须是无害的（`name` 是主键，天然去重）。
  static List<String> get seedProcessStatements => [
        for (var i = 0; i < Defaults.builtinProcesses.length; i++)
          "INSERT OR IGNORE INTO ${Tables.processPresets} "
              '(name, is_builtin, sort_order, created_at) VALUES '
              "('${Defaults.builtinProcesses[i].replaceAll("'", "''")}', 1, $i, 0)",
      ];

  /// v1 → v2：补「精确到分钟」「加班」两组字段。
  ///
  /// 迁移是**原地加列**，不改任何既有值：
  /// * `minute_of_day` 先用录入时刻的本地时分回填，老账的时间顺序至少有据可依；
  /// * 所有老流水 `overtime = 0`，等价于「非加班」，金额与升级前**完全一致**；
  /// * 玩具的加班单价默认 0（未设置），按倍率模式兜底，不会出现 0 元工资。
  static const List<String> migrateV1ToV2 = [
    'ALTER TABLE ${Tables.toys} '
        'ADD COLUMN overtime_price_ten_thousandth INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ${Tables.pieceRecords} '
        'ADD COLUMN minute_of_day INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ${Tables.pieceRecords} '
        'ADD COLUMN overtime INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ${Tables.pieceRecords} '
        'ADD COLUMN overtime_price_snapshot INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ${Tables.pieceRecords} '
        'ADD COLUMN overtime_multiplier INTEGER NOT NULL DEFAULT 1000',
    'ALTER TABLE ${Tables.adjustments} '
        'ADD COLUMN minute_of_day INTEGER NOT NULL DEFAULT 0',
    // 用录入时刻回填时分（created_at 是毫秒，先换算成秒再取本地时分）。
    "UPDATE ${Tables.pieceRecords} SET minute_of_day = "
        "CAST(strftime('%H', created_at / 1000, 'unixepoch', 'localtime') AS INTEGER) * 60 + "
        "CAST(strftime('%M', created_at / 1000, 'unixepoch', 'localtime') AS INTEGER)",
    "UPDATE ${Tables.adjustments} SET minute_of_day = "
        "CAST(strftime('%H', created_at / 1000, 'unixepoch', 'localtime') AS INTEGER) * 60 + "
        "CAST(strftime('%M', created_at / 1000, 'unixepoch', 'localtime') AS INTEGER)",
    'CREATE INDEX idx_records_date_minute ON ${Tables.pieceRecords}(date, minute_of_day)',
  ];

  /// v2 → v3：计时工资（工时 × 时薪）+ 常用工序表。
  ///
  /// 同样是原地加列：
  /// * 老调整项 `work_minutes = 0`、`hourly_rate_cents = 0`，即「直接填金额」，
  ///   金额 `amount_cents` 一分不动；
  /// * `process_presets` 新建后立刻灌入预置工序，
  ///   再按现有玩具档案里出现过的工序补一遍——这样升级后打开选择列表，
  ///   以前手打过的工序也都在里面，不用重新加。
  static const List<String> migrateV2ToV3 = [
    'ALTER TABLE ${Tables.adjustments} '
        'ADD COLUMN work_minutes INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ${Tables.adjustments} '
        'ADD COLUMN hourly_rate_cents INTEGER NOT NULL DEFAULT 0',
    '''
    CREATE TABLE ${Tables.processPresets} (
      name TEXT PRIMARY KEY NOT NULL,
      is_builtin INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    // 历史上手打过的工序全部沉淀为「自定义项」，排在预置项之后。
    'INSERT OR IGNORE INTO ${Tables.processPresets} '
        '(name, is_builtin, sort_order, created_at) '
        'SELECT DISTINCT TRIM(process), 0, 1000, '
        'CAST(strftime(\'%s\', \'now\') AS INTEGER) * 1000 '
        'FROM ${Tables.toys} WHERE TRIM(process) <> \'\'',
  ];

  /// v3 → v4：工人联系方式 + 结算状态表。
  ///
  /// * 电话/身份证号是**选填**，老档案统一补空串，
  ///   查询、结算、报表都不依赖这两个字段，升级后行为与之前一致；
  /// * `settlement_marks` 新表默认为空 = 所有历史账目都是「未结算」，
  ///   不会凭空把已经发过钱的月份标成未结算，也不会擅自标成已结算。
  static const List<String> migrateV3ToV4 = [
    'ALTER TABLE ${Tables.workers} '
        "ADD COLUMN phone TEXT NOT NULL DEFAULT ''",
    'ALTER TABLE ${Tables.workers} '
        "ADD COLUMN id_card TEXT NOT NULL DEFAULT ''",
    '''
    CREATE TABLE ${Tables.settlementMarks} (
      worker_id TEXT NOT NULL,
      month TEXT NOT NULL,
      is_settled INTEGER NOT NULL DEFAULT 0,
      settled_at INTEGER,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (worker_id, month)
    )
    ''',
    'CREATE INDEX idx_settlement_month ON ${Tables.settlementMarks}(month)',
  ];
}
