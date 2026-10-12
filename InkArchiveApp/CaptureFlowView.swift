import PhotosUI
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct CaptureFlowView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    @Environment(\.dismiss) private var dismiss
    let journalID: UUID
    @State private var capture: CapturedPage?
    @State private var preview: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var saving = false
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("待保存的手账页")
                    Text("确认整页清晰、没有遮挡。保存后将保留收到的原始图片文件。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        guard let capture else { return }
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                try await model.saveCapture(capture, in: journalID)
                                dismiss()
                            } catch { self.error = "保存失败，图片仍在当前预览中：\(error.localizedDescription)" }
                        }
                    } label: {
                        if saving { ProgressView().tint(.white) }
                        else { Label("保存原件", systemImage: "tray.and.arrow.down") }
                    }.buttonStyle(.borderedProminent).disabled(saving || importing)
                } else {
                    ContentUnavailableView {
                        Label("扫描一页回忆", systemImage: "doc.viewfinder")
                    } description: {
                        Text("在均匀光线下拍摄整页，也可以从相册导入已扫描的图片。")
                    }
                    if importing { ProgressView("读取图片…") }
                }
                HStack(spacing: 24) {
                    Button(capture == nil ? "拍摄" : "重新拍摄", systemImage: "camera") { showingCamera = true }
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("从相册选择", systemImage: "photo")
                    }
                }.disabled(saving || importing)
                Text("此版本为整页采集；裁边校正、结构标注与云端上传将在后续接入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(ArchiveTheme.paper)
            .navigationTitle("扫描页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { data in
                    do { try accept(data) }
                    catch { self.error = error.localizedDescription }
                    showingCamera = false
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                importing = true
                Task {
                    defer { importing = false; selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw AppFailure.invalidImage }
                        try accept(data)
                    } catch {
                        self.error = "读取失败。如果图片仅存在于 iCloud 相册，请先下载到本机。\(error.localizedDescription)"
                    }
                }
            }
            .alert("无法完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func accept(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeID = CGImageSourceGetType(source),
              let ext = UTType(typeID as String)?.preferredFilenameExtension,
              ["jpg", "jpeg", "heic", "heif", "png", "tiff"].contains(ext.lowercased()),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw AppFailure.invalidImage }
        capture = CapturedPage(data: data, fileExtension: ext)
        preview = UIImage(cgImage: thumbnail)
    }
}
