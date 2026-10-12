import InkArchiveCore
import SwiftUI
import ImageIO

struct ReaderView: View {
    let pages: [PageRecord]
    @State private var index: Int

    init(pages: [PageRecord], initialIndex: Int) {
        self.pages = pages
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    PageReaderScreen(pageID: page.id).tag(offset)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack {
                Button("上一页", systemImage: "chevron.left") { index -= 1 }
                    .disabled(index == 0)
                Spacer()
                Text("\(index + 1) / \(pages.count)").monospacedDigit()
                Spacer()
                Button("下一页", systemImage: "chevron.right") { index += 1 }
                    .disabled(index >= pages.count - 1)
            }.labelStyle(.iconOnly).padding(.horizontal, 24)
            Text("原件与校正图 · 保存在本机").font(.caption).foregroundStyle(.secondary)
        }.padding(.bottom, 20)
            .background(ArchiveTheme.paper)
            .navigationTitle("阅读")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reads files off the UI thread and downsamples large scans to a bounded preview.
struct AssetImage: View {
    @EnvironmentObject private var model: ArchiveAppModel
    let assetID: UUID
    var boxes: [SearchRecord] = []
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ZStack {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        ForEach(boxes) { record in
                            ForEach(Array(record.boxes.enumerated()), id: \.offset) { _, box in
                                Rectangle().stroke(ArchiveTheme.forest, lineWidth: 2)
                                    .background(ArchiveTheme.forest.opacity(0.08))
                                    .frame(width: box.width * size.width, height: box.height * size.height)
                                    .position(x: (box.x + box.width / 2) * size.width, y: (box.y + box.height / 2) * size.height)
                                    .accessibilityLabel(record.text)
                            }
                        }
                    }.frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.accessibilityLabel("手账页面图片")
            } else if failed {
                Label("原件暂不可读", systemImage: "exclamationmark.triangle").font(.caption)
            } else { ProgressView() }
        }
        .task(id: assetID) {
            image = nil
            failed = false
            guard let url = await model.assetURL(for: assetID) else { failed = true; return }
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: preview).pngData()
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { UIImage(data: $0) }
            failed = image == nil
        }
    }
}
