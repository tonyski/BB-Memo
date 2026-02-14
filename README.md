# BB Memo

BB Memo 是一个面向 iOS / macOS 的碎片化笔记应用，强调快速记录、标签组织、时间线回顾和跨设备同步。

本 README 基于当前仓库实现整理，尽量避免“计划中功能”与“已上线功能”混淆。

## 项目定位

- 快速记录：用最短路径保存灵感和待办
- 结构化沉淀：通过 `#标签` 与标签侧栏进行归档
- 可回顾：时间线浏览 + 搜索 + 时间筛选
- 跨端一致：优先使用 CloudKit，同步不可用时自动降级

## 当前已实现能力

### 1. 核心笔记流

- 新建、编辑、删除笔记
- 删除后进入回收站，可恢复或彻底删除
- 置顶逻辑：置顶内容优先展示
- 长文本折叠展示（卡片中按长度处理）
- iOS 首页时间线分页加载（默认每页 40 条）

### 2. 标签系统

- 从正文自动提取 `#标签`
- 编辑器内支持标签手动选择与新增
- 基于 `NaturalLanguage` 的关键词标签建议（含自动建议策略）
- 标签规范化与计数维护（`normalizedName` + `usageCount`）
- 删除标签时仅解绑关系，不删除笔记

### 3. 搜索与筛选

- 关键词搜索：匹配笔记内容和标签名
- 时间范围筛选（全部、今天、近一周、近一月、近三月）
- 搜索输入防抖（250ms）
- 搜索结果统一按“置顶优先 + 时间倒序”排序

### 4. 提醒能力

- 为每条笔记设置提醒时间
- 本地通知调度与取消（`UserNotifications`）
- 首次使用按需请求通知权限

### 5. flomo 导入

- 支持从 flomo 导出的 `.html` 文件导入
- 解析 HTML 为笔记内容和时间
- 导入幂等：通过来源标识与内容哈希去重，避免重复导入
- 导入时自动提取标签并建立关系

### 6. 图片文字提取（OCR）

- 编辑器支持“从相册提取文字”
- iOS 16+ 支持“相机实时扫描”并点按导入文字
- 识别出的文字会直接追加到当前笔记正文

### 7. 同步与容错

- 默认使用 SwiftData + CloudKit
- 启动容错降级链路：
  - `云端同步（推荐）`
  - `仅保存在本机`
  - `临时模式（退出后清空）`
- 提供同步诊断信息：账号状态、最近检查、日志
- 监听本地/远端变更通知刷新界面

### 8. 启动数据维护

App 启动后会执行一次维护任务：

- 补齐 Memo 派生字段（如 `contentHash`）
- 修复异常时间字段（`updatedAt < createdAt`）
- 重算标签使用计数

## 技术栈

- `SwiftUI`：跨平台界面与交互
- `SwiftData`：本地持久化与模型关系管理
- `CloudKit`：跨设备数据同步
- `UserNotifications`：提醒通知
- `NaturalLanguage`：关键词提取与标签建议
- `Combine`：同步信号监听与状态更新

## 数据模型（核心）

### Memo

- `stableID`：业务稳定 ID
- `content` / `contentHash`
- `createdAt` / `updatedAt`
- `isPinned`
- `reminderDate`
- `sourceType` / `sourceIdentifier` / `importedAt`
- `tags`（与 `Tag` 关系）

### Tag

- `name` / `normalizedName`
- `createdAt`
- `usageCount`
- `memos`（与 `Memo` 关系）

## 项目结构

```text
BB-Memo/
├── BB_MemoApp.swift                # App 入口、容器初始化、启动维护
├── ContentView.swift               # 平台入口布局（iOS/macOS）
├── Models/
│   ├── Memo.swift                  # Memo 模型与维护逻辑
│   └── Tag.swift                   # Tag 模型
├── Views/
│   ├── MemoTimelineView.swift      # 时间线与分页
│   ├── MemoEditorView.swift        # 编辑器
│   ├── MemoSearchView.swift        # 搜索页
│   ├── TagSidebarView.swift        # 标签侧栏
│   └── SettingsView.swift          # 设置与导入/同步诊断
└── Utilities/
    ├── SyncDiagnostics.swift       # CloudKit 状态与容错
    ├── FlomoImportService.swift    # 导入服务（幂等）
    ├── FlomoImporter.swift         # flomo HTML 解析
    ├── TagExtractor.swift          # 标签提取与建议
    ├── TagUsageCounter.swift       # 标签计数维护
    ├── MemoFilter.swift            # 统一排序与过滤
    ├── MemoMutationService.swift   # 统一写入入口（Memo/Tag）
    ├── ImageOCRService.swift       # 图片文字提取
    └── NotificationManager.swift   # 提醒管理
```

## 运行要求

> 以下版本来自当前 `project.pbxproj` 配置。

- Xcode（建议使用与工程配置匹配的最新版本）
- iOS Deployment Target: `26.2`
- macOS Deployment Target: `26.2`

## 本地运行

1. 克隆仓库

```bash
git clone https://github.com/tonyski/BB-Memo.git
cd BB-Memo
```

2. 用 Xcode 打开 `BB-Memo.xcodeproj`
3. 选择 iOS Simulator 或 macOS 目标并运行

## 同步与导入说明

### iCloud / CloudKit

- 需登录 iCloud 并为 App 开启 iCloud 权限
- 若 CloudKit 初始化失败，应用会自动回退到本地存储模式
- 可在设置页查看当前存储模式与账号状态

### flomo 导入

- 在设置页选择“导入 flomo 备份（HTML 文件）”
- 仅支持 flomo 导出的 HTML 文件
- 重复内容会按导入身份策略自动跳过

## 开发现状

- 当前仓库未包含独立测试 Target（无 `Tests` 目录）
- 主要质量保障来自运行时维护逻辑与数据一致性校正

## 贡献

欢迎提交 Issue 或 Pull Request。
