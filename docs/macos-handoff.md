# macOS 接续开发说明

## 本次交付

- 可直接打开的 iOS 17+ Xcode 工程和共享 InkArchive scheme。
- SwiftUI 书架、新建手账、页面列表、单页左右翻阅。
- AVFoundation 后置相机预览、拍摄、JPEG 数据接收、权限拒绝与相册导入回退。
- 相机 start/stop/configuration 在专用串行队列执行；拍摄固定为竖屏，匹配首版界面。
- 收到照片后先预览，点击确认才保存。保存期间禁用重复操作与交互式关闭。
- 原件 SHA-256 校验、文件复用、页面/封面/页序一次提交，元数据写入失败不会更新内存快照。
- 备份队列自动恢复中断的任务、重复入队合并、启动时重新扫描未备份原件。
- Swift Package 单元测试和 macOS GitHub Actions 测试/编译任务。

## 实现与方案的区别

当前使用 JSON 原子快照，尚未使用 Core Data。物件层只有基础数据校验，没有编辑、撤销、修订存档或阅读动画。备份队列只存储原件上传意图，没有 CloudKit 执行器、后台调度、传输凭证或恢复机制。界面不会出现“已备份”的误导提示。

本次设计图片是静态概念稿；iOS 界面通过原生控件实现，尚未完全匹配视觉稿。应用图标与商店资料需在发布前补齐。

## 首次验证

1. 运行核心包测试，再编译模拟器应用。失败时先修复编译或测试，不开始云端集成。
2. 模拟器从相册导入本地 JPG / PNG，确认页面显示正确，重启应用后页序和原件仍可读取。
3. 真机拍摄纸页，检查方向、可读性与照片数据；关闭再打开应用验证恢复。
4. 拒绝相机权限，确认“打开设置”可用，取消相机后仍可从相册导入。
5. 飞行模式下创建新手账、拍摄、保存并阅读，确认不依赖账号或网络。
6. 重复导入同一张图片允许成为两页，但原件文件复用；页面不会被去重消失。

## 下一步开发顺序

1. 采集阶段补入文档边缘识别、手动四角调整，所有校正结果独立存为衍生资产。
2. 在真实中文手写样本上验证 Vision OCR，首版先支持简体中文；记录识别框，并加入人工标签回退。
3. 本地存储迁移为 Core Data，建立版本日志与搜索索引，设计已有 JSON 数据的一次性迁移。
4. 结构标注连接 Layer 关系、补扫背面/下层/子页面，完善缺失资产提示。
5. 阅读器增加对应动效、缩放与减少动态效果支持。
6. 集成 CloudKit 私有数据库并配置开发团队 iCloud container，接入后台执行、重试、冲突与恢复。

## 测试边界

Windows 上只能验证工程文件引用、XML / plist、文件归档与 Git 完整性。本次 Swift 代码尚未经过编译与运行；GitHub Actions 和 macOS 首次运行的结果才是编译/测试依据。当前不是可发布至 App Store 的版本。

## 官方采集文档

- [AVCapturePhoto.fileDataRepresentation](https://developer.apple.com/documentation/avfoundation/avcapturephoto/filedatarepresentation%28%29)：取得照片文件数据及附件。
- [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)：选取后加载图片数据；远端相册资料可能需要网络。
