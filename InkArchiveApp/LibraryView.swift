import InkArchiveCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: ArchiveAppModel
    @State private var showingCreate = false
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.startupError {
                    ContentUnavailableView {
                        Label("资料库暂不可用", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await model.load() } }
                    }
                } else if !model.ready {
                    ProgressView("打开手账…")
                } else if model.journals.isEmpty {
                    ContentUnavailableView {
                        Label("留下纸上的回忆", systemImage: "books.vertical")
                    } description: {
                        Text("新建一本手账，然后拍摄或导入页面。原始图片保存在本机，离线也可以阅读。")
                    } actions: {
                        Button("新建手账", systemImage: "plus") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 24) {
                            ForEach(model.journals) { journal in
                                NavigationLink {
                                    JournalView(journalID: journal.id)
                                } label: {
                                    JournalCover(journal: journal)
                                }.buttonStyle(.plain)
                            }
                        }.padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ArchiveTheme.paper)
            .navigationTitle("我的手账")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建手账", systemImage: "plus") { showingCreate = true }
                        .disabled(!model.ready)
                }
            }
            .alert("新建手账", isPresented: $showingCreate) {
                TextField("例如：2026 日常", text: $title)
                Button("取消", role: .cancel) { title = "" }
                Button("创建") {
                    let journalTitle = title
                    title = ""
                    Task { await model.createJournal(title: journalTitle) }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("提示", isPresented: Binding(
                get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }
            )) {
                Button("知道了") { model.notice = nil }
            } message: { Text(model.notice ?? "") }
        }
    }
}

private struct JournalCover: View {
    let journal: JournalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(ArchiveTheme.forest)
                Rectangle().fill(.black.opacity(0.1)).frame(width: 12)
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "leaf").font(.largeTitle)
                    Text(journal.title).font(.headline).lineLimit(3)
                }.foregroundStyle(.white).padding(24)
            }.frame(height: 200).shadow(color: .black.opacity(0.12), radius: 6, y: 4)
            Text(journal.title).font(.headline).foregroundStyle(.primary)
            Text("\(journal.pageOrder.count) 页 · 仅本地").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
