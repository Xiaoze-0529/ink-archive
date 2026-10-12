import InkArchiveCore
import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    let journalID: UUID
    @State private var pages: [PageRecord] = []
    @State private var showingCapture = false
    @State private var query = ""
    @State private var matchingIDs: Set<UUID> = []

    private var visiblePages: [PageRecord] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pages : pages.filter { matchingIDs.contains($0.id) }
    }

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
                        ForEach(visiblePages) { page in
                            let index = pages.firstIndex { $0.id == page.id } ?? 0
                            NavigationLink {
                                ReaderView(pages: pages, initialIndex: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AssetImage(assetID: page.selectedCorrectedAssetID ?? page.baseAssetID)
                                        .frame(height: 180)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text("第 \(index + 1) 页").font(.subheadline)
                                    if let tags = page.tags, !tags.isEmpty {
                                        Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                    if visiblePages.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchiveTheme.paper)
        .navigationTitle(journal?.title ?? "手账")
        .searchable(text: $query, prompt: "搜索中文识别文字或人工标签")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("扫描页面", systemImage: "camera") { showingCapture = true }
            }
        }
        .sheet(isPresented: $showingCapture, onDismiss: { Task { await refresh() } }) {
            CaptureFlowView(journalID: journalID)
        }
        .task(id: query) { await refresh() }
    }

    private func refresh() async {
        let all = await model.pages(in: journalID)
        let matches = await model.searchPages(query: query, in: journalID)
        guard !Task.isCancelled else { return }
        pages = all
        matchingIDs = Set(matches.map(\.id))
    }
}
