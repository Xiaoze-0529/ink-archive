# InkArchiveCore

这是“墨迹档案”iOS 应用的离线优先核心包。它目前包含：

- 手账本、页面、物件层、资产与检索记录的数据模型。
- 原始扫描件的 SHA-256 去重与原子文件写入。
- 基于 JSON 的本地资料库原型，可在重启后恢复手账数据。
- 持久化备份队列，按原始件、元数据、衍生图、缩略图的顺序调度。
- 核心规则的单元测试。

## 在 Xcode 中开始

1. 在 macOS 上用 Xcode 打开 `Package.swift`。
2. 运行 `InkArchiveCoreTests`，确认本地资料库和队列规则通过。
3. 创建 iOS App target，并将本 Package 添加为本地依赖。
4. 先实现 `CaptureService`，将相机输出传给 `ArchiveRepository.importOriginal`；再接入页面校正、中文 OCR 和 CloudKit 备份适配器。

## 当前边界

该包实现的是可测试的离线资料库骨架，不包含 SwiftUI 界面、相机、OCR、CloudKit 传输或真实纸张动画。它们应分别作为上层 feature 模块接入，避免网络或 UI 状态影响原始档案的写入。
