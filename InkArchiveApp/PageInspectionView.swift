import InkArchiveCore
import SwiftUI

struct PageInspectionView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    @State private var page: PageRecord?
    @State private var records: [SearchRecord] = []
    @State private var tags = ""
    @State private var reference = ""
    @State private var working = false
    @State private var error: String?
    @State private var accuracy: OCRAccuracy?

    private var recognizedText: String { records.map(\.text).joined(separator: "\n") }

    var body: some View {
        NavigationStack {
            Form {
                Section("人工标签") {
                    TextField("旅行，日常，樱花…", text: $tags, axis: .vertical)
                    Text("标签独立保存。识别失败或没有文字时，仍可按标签搜索。").font(.caption).foregroundStyle(.secondary)
                }
                Section("简体中文识别") {
                    Text(status)
                    if let run = page?.ocrRun, let elapsed = run.elapsedMilliseconds {
                        Text("\(records.count) 个识别区域 · \(elapsed) ms · \(run.engineRevision ?? "Vision")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.text).textSelection(.enabled)
                            if let confidence = record.confidence {
                                Text("置信度 \(Int(confidence * 100))%（非准确率）")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("重新识别") {
                        working = true
                        Task {
                            await model.recognize(pageID: pageID)
                            await refresh(preserveDraft: true)
                            working = false
                        }
                    }.disabled(working || model.recognizingPageIDs.contains(pageID))
                    Text("文字用于检索，原件不会被改写。复杂手写、竖排和装饰性字体可能需要人工标签。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("手写样本验证") {
                    TextField("手动抄录页面全文，作为正确文本", text: $reference, axis: .vertical).lineLimit(3...8)
                    if let accuracy, let rate = accuracy.characterErrorRate {
                        Text("字符错误率 \((rate * 100).formatted(.number.precision(.fractionLength(1))))% · \(accuracy.editDistance) 处编辑 / \(accuracy.referenceCharacters) 字")
                    }
                    if reference.count > 3000 || recognizedText.count > 3000 {
                        Text("长篇样本请使用 macOS 批量验证工具计算错误率。")
                    }
                    Text("忽略空白，保留标点。此值只评价当前样本；并非系统对全部中文手写的准确率承诺。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(working)
            .navigationTitle("文字与标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        working = true
                        Task {
                            defer { working = false }
                            do {
                                try await model.saveTags(tags, for: pageID)
                                try await model.saveReference(reference, for: pageID)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(working || page == nil)
                }
            }
            .interactiveDismissDisabled(working)
            .task { await refresh(preserveDraft: false) }
            .task(id: reference + "\u{0}" + recognizedText) {
                let expected = reference, actual = recognizedText
                guard expected.count <= 3000, actual.count <= 3000 else { accuracy = nil; return }
                let result = await Task.detached(priority: .utility) { OCRAccuracy(reference: expected, recognized: actual) }.value
                guard !Task.isCancelled else { return }
                accuracy = result
            }
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var status: String {
        guard let run = page?.ocrRun else { return "尚未识别，可点击重新识别。" }
        switch run.state {
        case .recognized: return "识别完成，请对照页面检查。"
        case .noText: return "未识别到文字，请补充人工标签。"
        case .unsupported, .failed: return run.message ?? "识别暂不可用，请使用人工标签。"
        }
    }

    private func refresh(preserveDraft: Bool) async {
        page = await model.page(id: pageID)
        records = await model.searchRecords(for: pageID)
        if !preserveDraft {
            tags = (page?.tags ?? []).joined(separator: "，")
            reference = page?.ocrReferenceText ?? ""
        }
    }
}
