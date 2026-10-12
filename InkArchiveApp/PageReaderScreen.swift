import InkArchiveCore
import SwiftUI

struct PageReaderScreen: View {
    @EnvironmentObject private var model: ArchiveAppModel
    let pageID: UUID
    @State private var page: PageRecord?
    @State private var records: [SearchRecord] = []
    @State private var showCorrected = true
    @State private var showBoxes = false
    @State private var showingInspection = false
    @State private var correctionInput: CorrectionInput?
    @State private var loadingCorrection = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let page {
                let displayID = showCorrected ? (page.selectedCorrectedAssetID ?? page.baseAssetID) : page.baseAssetID
                if page.selectedCorrectedAssetID != nil {
                    Picker("图片版本", selection: $showCorrected) {
                        Text("原件").tag(false)
                        Text("校正图").tag(true)
                    }.pickerStyle(.segmented).padding(.horizontal, 20)
                }
                AssetImage(assetID: displayID, boxes: showBoxes ? records.filter { $0.sourceAssetID == displayID } : [])
                    .padding(12)
                HStack {
                    Button(showBoxes ? "隐藏识别框" : "显示识别框", systemImage: "text.viewfinder") { showBoxes.toggle() }
                        .disabled(records.isEmpty || records.first?.sourceAssetID != displayID)
                    Spacer()
                    Button("文字与标签", systemImage: "tag") { showingInspection = true }
                }.font(.subheadline).padding(.horizontal, 20)
                Button("重新调整四角", systemImage: "crop.rotate") {
                    loadingCorrection = true
                    Task {
                        defer { loadingCorrection = false }
                        do { correctionInput = try await model.correctionInput(for: page) }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(loadingCorrection || model.recognizingPageIDs.contains(pageID))
            } else { ProgressView().frame(maxHeight: .infinity) }
        }
        .task { await refresh() }
        .sheet(isPresented: $showingInspection, onDismiss: { Task { await refresh() } }) {
            PageInspectionView(pageID: pageID)
        }
        .sheet(item: $correctionInput) { input in
            DocumentCorrectionView(input: input) { corrected in
                try await model.saveCorrection(corrected, for: pageID)
                await refresh()
            }
        }
        .alert("无法调整", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func refresh() async {
        page = await model.page(id: pageID)
        records = await model.searchRecords(for: pageID)
    }
}
