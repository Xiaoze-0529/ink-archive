import Foundation
import InkArchiveCore
import SwiftUI

@MainActor
final class ArchiveAppModel: ObservableObject {
    @Published private(set) var journals: [JournalRecord] = []
    @Published private(set) var ready = false
    @Published private(set) var startupError: String?
    @Published var notice: String?

    private var repository: ArchiveRepository?
    private var backupQueue: BackupQueue?
    private var loading = false

    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let root = support.appendingPathComponent("InkArchive", isDirectory: true)
            repository = try ArchiveRepository(rootDirectory: root)
            await reload()
            startupError = nil
            ready = true
            do {
                backupQueue = try BackupQueue(storageURL: root.appendingPathComponent("BackupQueue.json"))
                try await reconcileQueue()
            } catch {
                notice = "本地手账可正常使用，但备份队列暂不可用：\(error.localizedDescription)"
            }
        } catch {
            startupError = "无法打开本地资料库：\(error.localizedDescription)"
        }
    }

    func createJournal(title: String) async {
        guard let repository else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await repository.createJournal(title: trimmed)
            await reload()
        } catch {
            notice = "创建失败：\(error.localizedDescription)"
        }
    }

    func saveCapture(_ capture: CapturedPage, in journalID: UUID) async throws {
        guard let repository else { throw AppFailure.storageUnavailable }
        _ = try await repository.importPage(data: capture.data, fileExtension: capture.fileExtension, into: journalID)
        await reload()
        // The image is already saved. A queue failure must not invite duplicate imports.
        do { try await reconcileQueue() }
        catch { notice = "页面已保存到本机，备份队列将在下次启动时重建。" }
    }

    func pages(in journalID: UUID) async -> [PageRecord] {
        guard let repository else { return [] }
        return await repository.pages(in: journalID)
    }

    func assetURL(for assetID: UUID) async -> URL? {
        guard let repository else { return nil }
        return try? await repository.assetURL(id: assetID)
    }

    private func reload() async {
        if let repository { journals = await repository.journals() }
    }

    private func reconcileQueue() async throws {
        guard let repository, let backupQueue else { return }
        for asset in await repository.originalAssetsAwaitingBackup() {
            _ = try await backupQueue.enqueue(SyncJob(entityType: .asset, entityID: asset.id, priority: .original))
        }
    }
}

enum AppFailure: LocalizedError {
    case storageUnavailable
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "本地资料库尚未就绪。"
        case .invalidImage: "无法读取这张图片，请重新选择。"
        }
    }
}

struct CapturedPage: Identifiable {
    let id = UUID()
    let data: Data
    let fileExtension: String
}

enum ArchiveTheme {
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let forest = Color(red: 0.22, green: 0.32, blue: 0.29)
}
