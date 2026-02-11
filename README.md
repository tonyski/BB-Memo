# BB Memo

BB Memo 是一款受 Flomo 启发的极简主义、跨平台（iOS & macOS）碎片化笔记应用。它旨在帮助用户快速记录灵感、思考和日常点滴，通过时间轴和标签系统高效管理碎片化信息。

## ✨ 特性

- **🚀 跨平台支持**：专为 iOS 和 macOS 设计，提供原生的交互体验。
- **📅 时间轴视图**：以时间流的形式展示笔记，回顾思考轨迹。
- **🏷️ 智能标签**：支持 `#标签` 语法，并具备自动标签提取功能，方便分类查找。
- **📌 置顶功能**：重要的思绪可以随时置顶，保持关注。
- **🔍 全文搜索**：强大的搜索功能，支持内容和标签的快速检索。
- **⏰ 提醒功能**：为 Memo 设置提醒，不错过任何重要的待办或回顾。
- **📥 数据导入**：支持从 Flomo 导出数据并快速导入到 BB Memo 中。
- **☁️ 云端同步**：基于 SwiftData 构建，支持跨设备同步。
- **🎨 现代审美**：采用玻璃拟态（Glassmorphism）和简约设计语言，提供极致的视觉享受。

## 🛠️ 技术栈

- **SwiftUI**：构建声明式用户界面。
- **SwiftData**：现代化的数据持久化框架。
- **NotificationCenter**：本地通知与提醒。
- **Combine / Concurrency**：高效处理异步逻辑和数据流。

## 📦 安装与运行

### 环境要求
- Xcode 15.0+
- iOS 17.0+ / macOS 14.0+

### 运行步骤
1. 克隆本仓库：
   ```bash
   git clone https://github.com/tonyski/BB-Memo.git
   ```
2. 使用 Xcode 打开 `BB-Memo.xcodeproj`。
3. 选择目标设备（iPhone 模拟器或 Mac）。
4. 点击 **Run** (Cmd + R) 运行项目。

## 🤝 贡献

欢迎提交 Issue 或 Pull Request 来改进 BB Memo！
