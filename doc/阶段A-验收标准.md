# 阶段 A · 验收标准（数据层）

> 配套《技术方案-V1.md》使用。阶段 A 只做**骨架 + 数据层**，不写任何业务界面。
> 本文件里的每条断言都是**可执行**的：跑 `flutter test` 必须全绿，`grep` 必须零命中。
> 不满足其中任意一条，阶段 A 视为未完成，不进入阶段 B。

---

## 1. 交付物清单

```
lib/
├─ main.dart                        # 能启动，显示一个占位页即可
├─ app.dart                         # MaterialApp + 主题（颜色取 §7.1）
├─ core/theme.dart                  # 颜色/字号常量，唯一来源
├─ data/
│  ├─ db.dart                       # 打开库、建表、迁移、PRAGMA
│  ├─ models/trip.dart
│  ├─ models/day.dart
│  ├─ models/photo.dart
│  ├─ models/import_item.dart
│  ├─ models/import_result.dart
│  ├─ dao/trip_dao.dart
│  ├─ dao/day_dao.dart
│  ├─ dao/photo_dao.dart
│  └─ repository.dart               # 页面唯一入口
test/
├─ db_schema_test.dart
├─ trip_repo_test.dart
├─ day_gen_test.dart
├─ photo_import_test.dart
├─ photo_delete_test.dart
└─ day_grouping_test.dart
```

**本阶段不写**：`features/` 下任何页面、任何 `CustomPaint`、任何弹层。

---

## 2. 接口契约（测试就按这个写）

```dart
// repository.dart
class TripRepo {
  Future<Trip> create({required String name, required DateTime start, required DateTime end});
  Future<List<Trip>> listAlive();
  Future<Trip?> find(String id);                        // 找不到返回 null，不兜底
  Future<void> rename(String id, String name);
  Future<void> updateDates(String id, DateTime start, DateTime end);
  Future<void> delete(String id);                       // 物理删除，级联
}

class PhotoRepo {
  Future<ImportResult> importBatch(String tripId, List<ImportItem> items);
  Future<int> countOf(String tripId);                   // 只数 deleted_at IS NULL
  Future<List<Photo>> byDay(String tripId, String? dayId);
  Future<void> softDelete(List<String> photoIds);
  Future<void> setCover(String photoId);                // 同行程内只有一个封面
  Future<void> updateInfo(String photoId,
      {DateTime? takenAt, double? lat, double? lng, String? place});
}

class ImportItem {
  final String uri;
  final String hash;          // SHA1，调用方算好传进来（DAO 不读文件）
  final DateTime? takenAt;
  final double? lat, lng;
  final int width, height;
}

class ImportResult {
  final int inserted;
  final int skipped;          // 因 UNIQUE(trip_id,hash) 被跳过
  final int failed;
  final Map<String, int> byDay;  // dayId -> 张数，'unknown' 表示时间未知
}
```

> **设计约束**：`importBatch` 不读文件、不解析 EXIF。
> 读文件与算哈希在调用方的 Isolate 里做，DAO 只负责落库。
> 这样 DAO 可以被单元测试完全覆盖，不需要真实图片。

---

## 3. 测试环境约定（这一步不做会直接卡住）

`flutter test` 跑在 Dart VM 上，**`sqflite` 默认不可用**。必须：

```yaml
dev_dependencies:
  sqflite_common_ffi: ^2.3.3     # ← 技术方案 §2.3 未列，阶段 A 补充
```

```dart
// test/helpers/db_helper.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await createSchema(db);        // 复用 lib 里的建表函数
  return db;
}
```

**每个测试用例用独立的 `inMemoryDatabasePath`**，不要共享一个库，否则用例之间互相污染。

### ⚠️ 三个必须留意的坑

1. **`PRAGMA foreign_keys = ON` 是"每连接"生效的。**
   必须在 `onConfigure` 里执行，写在建表语句里没用。不做这一步，`ON DELETE CASCADE` 会**静默失效**——删了行程，照片还在，而测试不会报错。

2. **内存库默认可能不认外键**，同上，靠 `onConfigure`。

3. **日期一律存 `'YYYY-MM-DD'` 字符串**，不要存 `DateTime.toIso8601String()`。
   否则字符串比较会带上时间，`BETWEEN '2026-10-02' AND '2026-10-06'` 会漏掉最后一天。

---

## 4. 单元测试清单

> 共 19 个用例。名称、前置、操作、断言都写死了，请按此实现，不要改断言口径。

### 4.1 `db_schema_test.dart`

**T01 表与索引齐备**

```
准备：openTestDb()
操作：查 sqlite_master
断言：
  - 存在表 trips / days / photos / imports
  - 存在索引 idx_photos_dedup
  - 存在唯一索引 idx_days_unique
```

**T02 外键约束已开启**

```
操作：PRAGMA foreign_keys
断言：返回值为 1
```

**T03 插入非法外键应失败**

```
准备：一个空的 photos 表
操作：INSERT INTO photos(trip_id='not-exist', ...)
断言：抛 DatabaseException
说明：这条用来反向证明外键真的在工作（T02 只证明"开关打开了"）
```

---

### 4.2 `trip_repo_test.dart`

**T04 新建行程后能查到**

```
操作：create(name:'测试', start:2026-10-02, end:2026-10-06)
断言：
  - 返回 Trip.id 非空
  - find(id) 不为 null，name == '测试'
  - listAlive().length == 1
```

**T05 找不到时返回 null（不许兜底）**

```
准备：库里已有 1 个行程
操作：find('不存在的id')
断言：返回 null
说明：原型 getTrip() 会返回 TRIPS[0]，这是要修掉的 bug
```

**T06 删除行程后，附属数据全部消失**

```
准备：create 行程 → 生成 5 天 → importBatch 5 张
操作：delete(tripId)
断言：
  - find(tripId) == null
  - SELECT COUNT(*) FROM days WHERE trip_id=? → 0
  - SELECT COUNT(*) FROM photos WHERE trip_id=? → 0
  - SELECT COUNT(*) FROM imports WHERE trip_id=? → 0
说明：纯靠级联，不写删除语句。若为 0 则证明外键生效
```

**T07 改名不影响其它字段**

```
准备：create → importBatch 3 张 → 记下 count
操作：rename(id, '新名字')
断言：name == '新名字'；countOf(id) 仍为 3
```

---

### 4.3 `day_gen_test.dart`

**T08 按起止日期生成正确天数**

```
操作：create(start:2026-10-02, end:2026-10-06)
断言：
  - days 表有 5 条
  - date 依次为 2026-10-02 … 2026-10-06
  - sort 为 0..4
```

**T09 改日期：延长**

```
准备：10-02 ~ 10-04（3 天），导入 2 张落在 10-03
操作：updateDates(id, 10-02, 10-06)
断言：
  - days 变为 5 条
  - 原有 10-03 的 day.id 不变（不能重建，否则照片会脱钩）
  - 那 2 张照片的 day_id 仍指向原 day
```

**T10 改日期：缩短**

```
准备：10-02 ~ 10-06（5 天），导入 1 张落在 10-06
操作：updateDates(id, 10-02, 10-04)
断言：
  - days 剩 3 条
  - 10-06 那条被删除
  - 那张照片没有被删，且 day_id 变为 NULL（ON DELETE SET NULL）
```

> 这条最容易做错。常见错误是"删天时把照片一起删了"，那是数据丢失。

---

### 4.4 `photo_import_test.dart`

**T11 首次导入**

```
准备：行程 10-02~10-06
操作：importBatch(10 张，其中 8 张有 takenAt、2 张 takenAt=null)
断言：
  - result.inserted == 10
  - result.skipped == 0
  - countOf == 10
  - result.byDay['unknown'] == 2
  - result.byDay 其余合计 == 8
```

**T12 重复导入同一批（去重）**

```
准备：已完成 T11
操作：用完全相同的 10 个 hash 再 importBatch 一次
断言：
  - result.inserted == 0
  - result.skipped == 10
  - countOf 仍为 10      ← 关键：不能翻倍
  - imports 表新增 1 条记录（记录"尝试导入"这个事实）
说明：张数只认 photos 表 COUNT(*)，不认 imports.count 累加
```

**T13 单条失败不中断整批**

```
准备：10 条数据，第 5 条 uri 为 null（模拟损坏）
操作：importBatch
断言：
  - result.failed == 1
  - result.inserted == 9
  - 抛异常？否。整个过程不抛
```

**T14 封面唯一**

```
准备：导入 3 张
操作：setCover(p1) → setCover(p2)
断言：
  - SELECT COUNT(*) FROM photos WHERE trip_id=? AND is_cover=1 → 1
  - 且这一张是 p2
```

---

### 4.5 `photo_delete_test.dart`

**T15 软删不计入张数，但记录还在**

```
准备：导入 5 张
操作：softDelete([p1, p2])
断言：
  - countOf == 3
  - SELECT COUNT(*) FROM photos WHERE trip_id=? → 5（记录未物理删）
  - p1.deleted_at 不为 null
```

**T16 软删的照片不出现在 byDay**

```
准备：同 T15
操作：byDay(tripId, dayId)
断言：结果中不含 p1 / p2
```

---

### 4.6 `day_grouping_test.dart`（纯函数，不需要数据库）

**T17 无时间 → 未分组**

```
断言：pickDayId(null, days) == null
```

**T18 凌晨归前一天**

```
准备：days = [10-02, 10-03]
操作：pickDayId(2026-10-02 03:59)
断言：返回 10-02 的 dayId
操作：pickDayId(2026-10-02 04:00)
断言：返回 10-02 的 dayId（4 点是分界，4 点后算当天）
```

**T19 行程范围外 → 未分组**

```
准备：days = [10-02, 10-03]
操作：pickDayId(2026-09-20 12:00)
断言：null
说明：不要硬塞到第一天
```

---

## 5. 集成级检查（SQL 直查，不写测试）

阶段 A 交付时，附上以下 4 条查询的**真实输出**：

```sql
-- ① 孤儿照片（应为 0）
SELECT COUNT(*) FROM photos p
LEFT JOIN trips t ON t.id = p.trip_id
WHERE t.id IS NULL;

-- ② 孤儿天（应为 0）
SELECT COUNT(*) FROM days d
LEFT JOIN trips t ON t.id = d.trip_id
WHERE t.id IS NULL;

-- ③ 同一行程多个封面（应为 0）
SELECT trip_id, COUNT(*) c FROM photos
WHERE is_cover = 1 GROUP BY trip_id HAVING c > 1;

-- ④ 重复照片（应为 0）
SELECT trip_id, hash, COUNT(*) c FROM photos
GROUP BY trip_id, hash HAVING c > 1;
```

---

## 6. 红线检查（grep）

```bash
# 阶段 A 不应该有任何界面代码
grep -rn "showModalBottomSheet\|showDialog(\|CustomPaint(" lib/features 2>/dev/null | wc -l
# 期望：0 或目录不存在

# 页面层不许直接摸数据库
grep -rn "rawQuery\|sqflite" lib/features 2>/dev/null | wc -l
# 期望：0

# 依赖版本没被擅自升级
git diff pubspec.lock
# 期望：只有 sqflite_common_ffi 这一条新增
```

---

## 7. 完成定义（DoD）

阶段 A 交付时，必须同时给出：

- [ ] `flutter analyze` 零 error（warning 不超过 5 条，且逐条说明）
- [ ] `flutter test` 全绿，**19 / 19 通过**
- [ ] 上述 4 条 SQL 的真实输出（截图或文本）
- [ ] 3 条 grep 的真实结果
- [ ] 文件清单（相对路径 + 一句话职责）
- [ ] **自行决定项清单**：文档没写、你自己定的地方
- [ ] **分歧点清单**：你认为文档哪里不合理，但已按文档实现

> 只回"阶段 A 已完成"不算交付。

---

## 8. 常见踩坑（照这个自查，能省半天）

| 现象 | 原因 | 处理 |
|---|---|---|
| 测试报 `databaseFactory not initialized` | 没调 `sqfliteFfiInit()` | 见 §3 |
| 删了行程，照片还在 | `PRAGMA foreign_keys` 没在 `onConfigure` 里开 | T03 会暴露 |
| 用例之间互相污染 | 共享了同一个内存库 | 每例新建 |
| 重复导入张数翻倍 | 用 `imports.count` 累加 | 只认 `COUNT(*)` |
| 改日期后照片全丢 | 删天时连带删了照片 | 靠 `ON DELETE SET NULL` |
| 最后一天的照片归不进 10-06 | 日期存了带时间的 ISO 字符串 | 只存 `YYYY-MM-DD` |

---

*阶段 A 验收标准 v1.0 · 配套《技术方案-V1.md》*
