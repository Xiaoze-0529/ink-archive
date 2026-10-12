import InkArchiveCore
import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    let journalID: UUID
    @State private var pages: [PageRecord] = []
    @State private var showingCapture = false

    private var journal: JournalRecord? { model.journals.first { $0.id == journalID } }

    var body: some View {
        Group {
            if pages.isEmpty {
                ContentUnavailableView {
                    Label("保存第一张手账页", systemImage: "doc.viewfinder")
                } description: {
                    Text("拍摄整页原件。剪贴物、背面和展开页的标注将在下一阶段接入。")
                } actions: {
                    Button("扫描页面", systemImage: "camera") { showingCapture = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 20) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            NavigationLink {
                                ReaderView(pages: pages, initialIndex: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AssetImage(assetID: page.baseAssetID)
                                        .frame(height: 180)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text("第 \(index + 1) 页").font(.subheadline)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchiveTheme.paper)
        .navigationTitle(journal?.title ?? "手账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("扫描页面", systemImage: "camera") { showingCapture = true }
            }
        }
        .sheet(isPresented: $showingCapture, onDismiss: { Task { await refresh() } }) {
            CaptureFlowView(journalID: journalID)
        }
        .task { await refresh() }
    }

    private func refresh() async { pages = await model.pages(in: journalID) }
}
