# 墨迹档案 · Ink Archive

iOS 手写手账归档应用。扫描原件保存在本机，页面阅读离线可用；剪贴、夹页、折页和中文手写索引将逐步接入。

## 当前可用流程

新建手账 → 真机拍摄 / 相册导入 → 自动检测边缘 / 手动调整四角 → 原件与独立校正图保存 → 本机简体中文 OCR → 页面列表 / 文字与标签搜索 → 原件、校正图与识别框阅读。

相机采集使用 AVFoundation 的 `fileDataRepresentation()`，保留接收到的 JPEG 文件及其元数据，不重新编码为预览图。相册导入保存 PhotosPicker 返回的文件数据；仅在 iCloud 相册中的图片可能需要先联网下载。

工程已配置 iPhone / iOS 17+，本地 Swift Package 无第三方依赖。自动边缘只是建议选区，用户可拖动四角确认、恢复整页或直接保存原件。每次校正追加独立资产，保存原件引用、四角参数与尺寸；阅读器可随时切回原件。尚未接入的功能：去阴影与墨迹增强、结构标注界面、物件动画、iCloud 真实上传与恢复。备份队列已落盘，界面如实显示“仅本地”。

OCR 首版使用 Vision 的 `zh-Hans` 配置，保存每行文字、识别框、置信度和实际图片版本；无文字或识别失败时保留人工标签检索。真实手写效果需要用你的页面验证，仓库没有用户的手写样本。阅读器的“文字与标签”可人工抄录正确文本来评价当前样本，也可用 [macOS 批量工具](docs/capture-ocr-testing.md) 生成本地验证报告。

## 在 macOS 上继续

1. 克隆本仓库，用 Xcode 16+ 打开 `InkArchive.xcodeproj`（不需要生成工程）。
2. 选择 `InkArchive` scheme 与 iPhone 模拟器，运行应用。模拟器用相册导入测试。
3. 连接 iPhone，在 Signing & Capabilities 选择你的开发团队，并将 `com.inkarchive.app` 改为自己可签名的 Bundle Identifier。
4. 真机首次拍摄时允许相机权限；照片仅保存在应用沙盒，不会写入系统相册。
5. 打开 `InkArchiveCore/Package.swift` 的独立 Xcode 窗口运行包测试，或在终端执行下列命令。

```sh
git clone https://github.com/Xiaoze-0529/ink-archive.git
cd ink-archive
open InkArchive.xcodeproj
```

验证命令：

```sh
swift test --package-path InkArchiveCore
xcodebuild -project InkArchive.xcodeproj -scheme InkArchive \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

本轮代码提交 `9caa887` 通过了 19 项测试（含实际 Apple 图像 API 的合成夹具）与 iPhone 模拟器编译。[本轮验证记录](https://github.com/Xiaoze-0529/ink-archive/actions/runs/38230711246)。相机、四角拖拽与真实手写效果仍需真机运行验收。

## 文件布局

- `InkArchiveApp/`：SwiftUI 界面、相机控制器、扫描确认流程。
- `InkArchive.xcodeproj/`：应用 target、共享 scheme 与本地 Package 引用。
- `InkArchiveCore/`：模型、原件库、持久化 JSON 资料库、备份队列及测试。
- `Design/`：前三轮视觉概念稿与产品结构图源文件，作为设计参考。
- 三份产品 / 技术文档：保存产品范围、目标架构、排期和数据契约。
- `docs/macos-handoff.md`：当前实现状态、运行验收与后续开发顺序。

本地 JSON 资料库是验证阶段实现；产品蓝图中的 Core Data / SQLite 迁移尚待完成。不要将用户原件、应用沙盒、签名证书或凭据提交到仓库。
