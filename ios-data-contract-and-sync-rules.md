# 墨迹档案：iOS 数据契约与同步规则 v1

## 1. 总则

本契约将“纸本档案”与“可编辑的数字阅读效果”拆开：

- **档案资产**为追加式数据。原始扫描件以内容校验值识别，不能覆盖。
- **编辑数据**为可版本化数据。页面顺序、物件位置、裁切与互动类型可以修改、撤销和同步。
- **同步任务**只存在本地。它记录待传输工作，不是用户手账内容的一部分。

所有实体均以 UUID 作为 `id`，时间使用 UTC ISO 8601，修改由单调递增的 `revision` 与 `updatedAt` 共同标记。

## 2. 核心实体

### JournalRecord

```text
id: UUID
title: String
coverAssetId: UUID?
pageOrder: [UUID]
tags: [String]
dateStart: Date?
dateEnd: Date?
revision: Int
createdAt / updatedAt: Date
deletedAt: Date?
```

约束：`pageOrder` 中的页面必须属于该 `JournalRecord`；手账本删除先写入 `deletedAt`，不会立即清除文件。

### PageRecord

```text
id: UUID
journalId: UUID
baseAssetId: UUID
pageKind: normal | spread | insert | foldout
layerOrder: [UUID]
scanStatus: complete | needsSupplement | needsReview
revision: Int
createdAt / updatedAt: Date
deletedAt: Date?
```

约束：`baseAssetId` 必须指向 `role = pageFront` 的原始扫描件；任一缺少的关联资产必须反映为 `needsSupplement`。

### LayerRecord

```text
id: UUID
pageId: UUID
zIndex: Int
frame: normalizedRect
mask: normalizedPolygon?
interactionType: fixed | lift | insert | foldout
hingeEdge: top | right | bottom | left?
frontAssetId: UUID?
backAssetId: UUID?
underlayAssetId: UUID?
linkedPageIds: [UUID]
revision: Int
createdAt / updatedAt: Date
deletedAt: Date?
```

约束：

- 坐标相对 `PageRecord` 的主扫描图归一化为 `0...1`，避免因设备尺寸改变而漂移。
- `lift` 必须有 `hingeEdge`；背面与下层资产可为空，但阅读器只能渲染已有部分。
- `insert` 至少有一个 `linkedPageId`；`foldout` 使用有序 `linkedPageIds`。
- `frame`、`mask`、`interactionType` 的变更视为一次完整的 `LayerRecord` 修订。

### AssetRecord

```text
id: UUID
contentHash: SHA-256
kind: original | corrected | enhanced | thumbnail | export
role: pageFront | pageBack | layerFront | layerBack | underlay | foldoutSegment
sourceAssetId: UUID?
relativePath: String
pixelWidth / pixelHeight: Int
byteCount: Int
captureAt: Date
createdAt: Date
backupState: localOnly | queued | uploading | backedUp | retryNeeded
deletedAt: Date?
```

约束：

- `kind = original` 的 `sourceAssetId` 必须为空且文件不可就地修改。
- 衍生资产的 `sourceAssetId` 最终必须追溯到一个原始资产。
- `contentHash` 相同的资产不重复写入文件库；实体可复用同一文件引用。

### SearchRecord

```text
id: UUID
ownerType: page | layer
ownerId: UUID
text: String
language: zh-Hans
boxes: [normalizedRect]
sourceAssetId: UUID
engineRevision: String
createdAt: Date
```

约束：搜索结果只能跳转和高亮，不能驱动页面图像重绘。

### SyncJob（仅本地）

```text
id: UUID
entityType: metadata | asset | tombstone
entityId: UUID
dependencyIds: [UUID]
priority: original | metadata | derivative | thumbnail
attemptCount: Int
nextAttemptAt: Date
lastErrorCode: String?
state: waiting | running | completed | retryNeeded | blocked
```

约束：原始资产上传依赖其 `AssetRecord` 元数据已创建；缩略图与增强图不能阻塞原件的备份完成。

## 3. 本地文件布局

```text
Application Support/
  ArchiveStore.sqlite
  Assets/
    originals/<sha256>.<extension>
    derived/<source-asset-id>/<version>.<extension>
    exports/<export-id>.pdf
  Thumbnails/<asset-id>.jpg
```

文件写入采用“临时文件 → 校验 hash → 原子改名 → 数据库事务”的顺序。若应用在任一步被终止，下次启动清理未被数据库引用的临时文件；绝不删除已被 `AssetRecord` 引用的原始文件。

## 4. 本地写入事务

### 扫描页面

1. 相机输出写入临时文件。
2. 计算内容校验值并移动至 `originals/`。
3. 在单个数据库事务内写入 `AssetRecord`、`PageRecord` 与 `JournalRecord.pageOrder` 更新。
4. 写入高优先级原件备份任务。
5. 校正、缩略图和 OCR 可在事务之后异步生成。

### 编辑结构

1. 用户完成一次拖拽、裁切或类型切换后创建新的 `LayerRecord.revision`。
2. 写入本地变更记录与元数据同步任务。
3. 阅读器只读取最后一个已提交的修订，未提交拖拽不写入同步队列。

### 删除

1. 写入 `deletedAt` 和本地 tombstone 同步任务。
2. 资产进入最近删除，保留到设定的恢复期结束。
3. 仅在 tombstone 已备份且无记录引用文件时，执行物理清理。

## 5. 云端记录边界

| 云端记录 | 保存内容 | 不保存内容 |
| --- | --- | --- |
| Journal | 手账本元数据、页面顺序、修订 | 图片二进制 |
| Page | 页面的资产引用、类型、状态 | 衍生图像本体 |
| Layer | 位置、蒙版、交互关系、修订 | 动画帧或生成内容 |
| Asset | 校验值、尺寸、类型、云端文件引用 | OCR 正文的副本 |
| Search | 可选的恢复索引 | 原图替代文本 |

首版只使用用户私有空间；记录 schema 采用新增字段而不是删除或重命名既有字段的演进方式。

## 6. 冲突与合并

### 资产

原始资产按 `contentHash` 去重，永不互相覆盖。不同哈希即使同一页面也都保留，交由用户选择是否加入页面。

### 页面顺序

页面排序产生一个新的有序列表修订。若两个设备基于同一修订离线排序，则保留两份排序修订，优先显示最新修改，并提供“采用此顺序 / 保留另一顺序”选择。

### 物件层

同一 `LayerRecord` 同时被不同设备修改时，不做字段级静默合并。保留本地与云端两个修订，阅读器暂时使用本地最新修订，结构标注页显示“需要选择版本”。

### 删除与编辑

删除优先产生 tombstone，但不立即物理清理。若另一设备存在较新的编辑，恢复为“需要确认”状态，由用户决定保留还是删除。

## 7. 同步状态机

```text
localOnly
  → queued
  → uploading
  → backedUp
  ↘ retryNeeded → queued
  ↘ blocked (未登录 iCloud / 空间不足 / 需要用户处理)
```

- 队列按“原始件 → 元数据 → 衍生图 → 缩略图”调度。
- 网络不可用或系统终止时，`uploading` 在重启后重置为 `queued`，并保留已确认上传的结果。
- 连续失败采用退避重试；用户手动点“立即备份”可绕过下一次计划时间，但不跳过权限或网络限制。

## 8. 架构验证任务（第 1 周）

| 日程 | 验证内容 | 通过标准 |
| --- | --- | --- |
| 第 1 天 | 初始化本地数据库与资产文件库 | 创建空手账本、重启后仍可打开 |
| 第 2 天 | 原件原子写入与 hash 去重 | 导入相同图片不产生重复原件 |
| 第 3 天 | 页面与物件层事务 | 添加、撤销、重启后的顺序一致 |
| 第 4 天 | 中文 OCR 试验与坐标保存 | 可搜索样本中文字并跳至正确区域 |
| 第 5 天 | 离线备份队列模拟 | 飞行模式扫描后，恢复网络可按优先级继续 |

## 9. 单元与集成测试基线

- 资产写入中断、校验失败、无磁盘空间、重复导入。
- Layer 类型转换与缺失关联资产的阅读器回退。
- OCR 结果为空、语言不可用、低置信度结果与手动标签共存。
- 飞行模式、iCloud 未登录、网络抖动、系统重启与用户强制关闭。
- 两个离线修订、删除与编辑冲突、恢复最近删除。
