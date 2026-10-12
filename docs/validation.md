# 验证记录

## 采集校正与简体中文 OCR

2026-10-12，代码提交 `9caa8874c2328a754d03a499da09e0aa174b89f4`。

[本轮 GitHub Actions 运行记录](https://github.com/Xiaoze-0529/ink-archive/actions/runs/38230711246) 为 success：10 个 App 源文件的工程引用检查通过；19 项核心/图像处理测试零失败、未跳过；iPhone 模拟器 Debug 编译成功。

新增覆盖：合法/交叉/过小四角、EXIF 方向、实际 Vision 边缘检测、Core Image 校正、原件独立保留、多校正版本、中文 Vision 识别及归一化框、标签回退、旧资料可解码、过时识别结果拒绝和字符错误率计算。实际 Apple API 使用运行时生成的矩形图和印刷中文夹具，没有真实中文手写样本；不据此宣称手写准确率。

此记录之后的文档提交只更新说明。真实手写、拖拽触感、相机权限与真机运行验收按 [统一测试指南](capture-ocr-testing.md) 完成。

## 初始工程

2026-10-12，代码提交 `3c5c806eaace43d932a5d185005e22b8b7d801ff`。

[GitHub Actions 运行记录](https://github.com/Xiaoze-0529/ink-archive/actions/runs/38221224074) 为 success；build job 内的三项检查均成功：

- 工程结构检查：7 个 App Swift 源文件、项目对象引用、相机权限 plist 与共享 scheme。
- `swift test`：ArchiveRepositoryTests 7 项、BackupQueueTests 3 项，共 10 项测试，0 个失败。
- `xcodebuild`：Debug / generic iOS Simulator / 无签名，输出 BUILD SUCCEEDED。

测试覆盖原件持久化、校验、角色引用、去重、事务失败回退、备份优先级、依赖、去重入队与中断恢复。它们不代表相机已经通过真机测试，也不代表尚未接入的 OCR 或 CloudKit 能力已经实现。
