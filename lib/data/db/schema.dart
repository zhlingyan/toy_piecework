import '../../core/constants.dart';

/// 数据库结构定义（版本 1）。
///
/// 索引原则：日期、工人、删除标记三条高频过滤路径全部建索引。
/// 不启用外键约束——历史流水必须能在档案归档后继续存在，
/// 引用完整性由仓储层保证（插入前自动补建缺失档案）。
class Schema {
  Schema._();

  static const int version = 1;

  static const List<String> createStatements = [
    '''
    CREATE TABLE ${Tables.workers} (
      id TEXT PRIMARY KEY NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL,
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
      worker_id TEXT NOT NULL,
      toy_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      toy_name_snapshot TEXT NOT NULL,
      process_snapshot TEXT NOT NULL,
      unit_price_snapshot INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      subtotal_cents INTEGER NOT NULL,
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
      worker_id TEXT NOT NULL,
      worker_name_snapshot TEXT NOT NULL,
      type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      remark TEXT NOT NULL,
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (amount_cents > 0),
      CHECK (type IN ('bonus','hourly','deduction','advance'))
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
    // ---- 索引 ----
    'CREATE INDEX idx_workers_archived ON ${Tables.workers}(is_archived)',
    'CREATE INDEX idx_workers_code ON ${Tables.workers}(code)',
    'CREATE INDEX idx_toys_archived ON ${Tables.toys}(is_archived)',
    'CREATE INDEX idx_toys_name_process ON ${Tables.toys}(name, process)',
    'CREATE INDEX idx_records_date ON ${Tables.pieceRecords}(date)',
    'CREATE INDEX idx_records_worker_date ON ${Tables.pieceRecords}(worker_id, date)',
    'CREATE INDEX idx_records_toy_date ON ${Tables.pieceRecords}(toy_id, date)',
    'CREATE INDEX idx_records_deleted ON ${Tables.pieceRecords}(deleted_at)',
    'CREATE INDEX idx_adjustments_date ON ${Tables.adjustments}(date)',
    'CREATE INDEX idx_adjustments_worker_date ON ${Tables.adjustments}(worker_id, date)',
    'CREATE INDEX idx_adjustments_deleted ON ${Tables.adjustments}(deleted_at)',
  ];

  /// 恢复/导入前清空用，顺序无关（无外键）。
  static const List<String> clearStatements = [
    'DELETE FROM ${Tables.pieceRecords}',
    'DELETE FROM ${Tables.adjustments}',
    'DELETE FROM ${Tables.toys}',
    'DELETE FROM ${Tables.workers}',
    'DELETE FROM ${Tables.lockedMonths}',
  ];
}
