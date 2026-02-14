# BB Memo

BB Memo 是一款面向 iOS / macOS 的轻量笔记应用，强调快速记录、标签整理、时间线回顾与跨设备同步。

## 功能概览

- 快速新建、编辑、置顶、软删除与回收站恢复
- `#标签` 自动提取，支持标签筛选与搜索
- 搜索 + 时间范围筛选（今天 / 近一周 / 近一月 / 近三月）
- 笔记提醒（本地通知）
- 图片文字提取（OCR）：相册提取 + 相机实时扫描（iOS 16+）
- flomo HTML 导入（按来源标识 + 内容哈希去重）
- SwiftData + CloudKit 同步，失败时自动降级到本地/临时模式

## 技术栈

- `SwiftUI`
- `SwiftData`
- `CloudKit`
- `UserNotifications`
- `Vision` / `VisionKit`
- `NaturalLanguage`

## 数据模型

### Memo

核心持久化字段：

- `stableID: UUID`：业务稳定 ID（用于提醒标识和跨会话逻辑）
- `content: String`
- `contentHash: String`：归一化内容哈希（用于导入去重）
- `createdAt: Date`
- `updatedAt: Date`
- `isPinned: Bool`
- `isDeleted: Bool`：兼容旧字段
- `deletedAt: Date?`：回收站状态单一判定来源（`deletedAt != nil`）
- `reminderDate: Date?`
- `sourceType: String?`
- `sourceIdentifier: String?`
- `importedAt: Date?`
- `tags: [Tag]?`：与 `Tag` 的多对多关系

关键派生属性：

- `isInRecycleBin`：是否在回收站（基于 `deletedAt`）
- `reminderIdentifier`：稳定提醒 ID（基于 `stableID.uuidString`）
- `importIdentity`：导入幂等键（优先 `sourceType:sourceIdentifier`，否则 `hash + createdAt`）

### Tag

核心持久化字段：

- `name: String`
- `normalizedName: String`：规范化名（小写，用于稳定排序/匹配）
- `createdAt: Date`
- `usageCount: Int`：被多少条 Memo 使用
- `memos: [Memo]?`：与 `Memo` 的多对多关系

## 运行要求

- Xcode（建议最新稳定版）
- iOS Deployment Target: `17.0`
- macOS Deployment Target: `14.0`

## 本地运行

```bash
git clone https://github.com/tonyski/BB-Memo.git
cd BB-Memo
open BB-Memo.xcodeproj
```

在 Xcode 中选择 iOS Simulator 或 macOS 目标运行即可。

## 同步与导入说明

- iCloud 同步需用户登录 iCloud 并授权
- 若 CloudKit 不可用，应用会自动降级到本地或临时模式
- flomo 导入入口在设置页，仅支持 flomo 导出的 HTML 文件

