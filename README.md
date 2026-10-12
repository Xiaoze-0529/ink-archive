# 墨迹档案 · Ink Archive

iOS 手写手账归档应用。扫描原件保存在本机，页面阅读离线可用；剪贴、夹页、折页和中文手写索引将逐步接入。

## 当前可用流程

新建手账 → 真机拍摄 / 相册导入 → 原件预览 → 确认保存 → 页面列表 → 左右翻阅 → 退出并重启后恢复。

相机采集使用 AVFoundation 的 `fileDataRepresentation()`，保留接收到的 JPEG 文件及其元数据，不重新编码为预览图。相册导入保存 PhotosPicker 返回的文件数据；仅在 iCloud 相册中的图片可能需要先联网下载。

工程已配置 iPhone / iOS 17+，本地 Swift Package 无第三方依赖。尚未接入的功能：透视裁边与增强、结构标注界面、物件动画、OCR 搜索、iCloud 真实上传与恢复。备份队列已落盘，界面如实显示“仅本地”。

## 在 macOS 上继续

1. 克隆本仓库，用 Xcode 16+ 打开 `InkArchive.xcodeproj`（不需要生成工程）。
2. 选择 `InkArchive` scheme 与 iPhone 模拟器，运行应用。模拟器用相册导入测试。
3. 连接 iPhone，在 Signing & Capabilities 选择你的开发团队，并将 `com.inkarchive.app` 改为自己可签名的 Bundle Identifier。
4. 真机首次拍摄时允许相机权限；照片仅保存在应用沙盒，不会写入系统相册。
5. 打开 `InkArchiveCore/Package.swift` 的独立 Xcode 窗口运行包测试，或在终端执行下列命令。

```sh
swift test --package-path InkArchiveCore
xcodebuild -project InkArchive.xcodeproj -scheme InkArchive \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions 在 macOS 上运行同样的包测试与模拟器编译。推送后需查看实际运行结果；当前 Windows 开发环境无法执行 Xcode 编译、Swift 测试或真机验收。

## 文件布局

- `InkArchiveApp/`：SwiftUI 界面、相机控制器、扫描确认流程。
- `InkArchive.xcodeproj/`：应用 target、共享 scheme 与本地 Package 引用。
- `InkArchiveCore/`：模型、原件库、持久化 JSON 资料库、备份队列及测试。
- `Design/`：前三轮视觉概念稿与产品结构图源文件，作为设计参考。
- 三份产品 / 技术文档：保存产品范围、目标架构、排期和数据契约。
- `docs/macos-handoff.md`：当前实现状态、运行验收与后续开发顺序。

本地 JSON 资料库是验证阶段实现；产品蓝图中的 Core Data / SQLite 迁移尚待完成。不要将用户原件、应用沙盒、签名证书或凭据提交到仓库。
