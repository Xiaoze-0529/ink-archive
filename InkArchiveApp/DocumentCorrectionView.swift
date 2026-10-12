import InkArchiveCore
import SwiftUI

struct DocumentCorrectionView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    @Environment(\.dismiss) private var dismiss
    let input: CorrectionInput
    /// A completed crop is passed back only after generating the full corrected file.
    let onApply: (CorrectedDocument) async throws -> Void
    @State private var image: UIImage?
    @State private var quad = DocumentQuad.fullImage
    @State private var automaticQuad: DocumentQuad?
    @State private var preparing = true
    @State private var applying = false
    @State private var status = "正在识别页面边缘…"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    CornerCanvas(image: image, quad: $quad).disabled(applying)
                    Text(quad.isValid ? status : "四角位置无效，请避免交叉或重合。")
                        .font(.subheadline).foregroundStyle(quad.isValid ? Color.secondary : Color.red)
                    HStack {
                        Button("自动边缘") {
                            if let automaticQuad { quad = automaticQuad; status = "已采用检测边缘，请确认没有裁掉剪贴内容。" }
                        }.disabled(automaticQuad == nil || applying)
                        Spacer()
                        Button("恢复整页") { quad = .fullImage; status = "拖动四个角调整选区。" }.disabled(applying)
                    }
                    Button {
                        applying = true
                        Task {
                            defer { applying = false }
                            do {
                                let result = try await model.correctDocument(data: input.data, quad: quad)
                                try await onApply(result)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        if applying { ProgressView("生成校正图…") }
                        else { Text("使用此校正") }
                    }.buttonStyle(.borderedProminent).disabled(!quad.isValid || applying)
                } else if preparing { ProgressView(status).frame(maxHeight: .infinity) }
                else { ContentUnavailableView("图片暂不可用", systemImage: "photo.badge.exclamationmark", description: Text(status)) }
                Text("原件始终保留。拖动四角可裁边并校正透视。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(ArchiveTheme.paper)
                .navigationTitle("调整四角")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(applying) }
                }
                .interactiveDismissDisabled(applying)
                .task {
                    do {
                        let result = try await model.prepareDocument(data: input.data)
                        guard !Task.isCancelled else { return }
                        image = UIImage(data: result.previewData)
                        automaticQuad = result.detectedQuad
                        quad = input.initialQuad ?? result.detectedQuad ?? .fullImage
                        status = result.detectedQuad == nil ? "未找到可靠边缘，请手动拖动四角。" : "已找到页面边缘，请拖动四角确认。"
                    } catch { status = error.localizedDescription }
                    preparing = false
                }
                .alert("校正失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("知道了") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
}

private struct CornerCanvas: View {
    let image: UIImage
    @Binding var quad: DocumentQuad
    private let names = ["左上角", "右上角", "右下角", "左下角"]

    var body: some View {
        GeometryReader { proxy in
            let scale = min((proxy.size.width - 44) / image.size.width, (proxy.size.height - 44) / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            ZStack {
                Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                ZStack {
                    Path { path in
                        let points = quad.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        path.addLines(points)
                        path.closeSubpath()
                    }.stroke(quad.isValid ? ArchiveTheme.forest : Color.red, lineWidth: 3)
                    ForEach(0..<4, id: \.self) { corner in
                        let point = quad.points[corner]
                        Circle().fill(.white).overlay(Circle().stroke(ArchiveTheme.forest, lineWidth: 3))
                            .frame(width: 24, height: 24).padding(10).contentShape(Rectangle())
                            .position(x: point.x * size.width, y: point.y * size.height)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crop-image"))
                                .onChanged { value in
                                    guard size.width > 0, size.height > 0 else { return }
                                    quad.setCorner(corner, to: .init(
                                        x: min(1, max(0, value.location.x / size.width)),
                                        y: min(1, max(0, value.location.y / size.height))
                                    ))
                                })
                            .accessibilityLabel(names[corner])
                            .accessibilityValue("横向 \(Int(point.x * 100))%，纵向 \(Int(point.y * 100))%")
                    }
                }.frame(width: size.width, height: size.height).coordinateSpace(name: "crop-image")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minHeight: 240)
    }
}
