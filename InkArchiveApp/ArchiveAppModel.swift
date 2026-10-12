import Foundation
import InkArchiveCore
import SwiftUI

@MainActor
final class ArchiveAppModel: ObservableObject {
    @Published private(set) var journals: [JournalRecord] = []
    @Published private(set) var ready = false
    @Published private(set) var startupError: String?
    @Published var notice: String?
    @Published private(set) var recognizingPageIDs: Set<UUID> = []
    private let documentProcessor = DocumentProcessor()
    private let ocrService = OCRService()

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

    func saveCapture(_ capture: CapturedPage, correction: CorrectedDocument? = nil, tags: [String] = [], in journalID: UUID) async throws {
        guard let repository else { throw AppFailure.storageUnavailable }
        let page = try await repository.importPage(data: capture.data, fileExtension: capture.fileExtension,
                                                    into: journalID, correction: correction, tags: tags)
        await reload()
        // The image is already saved. A queue failure must not invite duplicate imports.
        do { try await reconcileQueue() }
        catch { notice = "页面已保存到本机，备份队列将在下次启动时重建。" }
        // OCR is secondary: failure never rolls back a successfully archived image.
        await recognize(pageID: page.id)
    }

    func pages(in journalID: UUID) async -> [PageRecord] {
        guard let repository else { return [] }
        return await repository.pages(in: journalID)
    }

    func assetURL(for assetID: UUID) async -> URL? {
        guard let repository else { return nil }
        return try? await repository.assetURL(id: assetID)
    }

    func page(id: UUID) async -> PageRecord? { await repository?.page(id: id) }

    func prepareDocument(data: Data) async throws -> DocumentPreparation {
        try await documentProcessor.prepare(data: data)
    }

    func correctDocument(data: Data, quad: DocumentQuad) async throws -> CorrectedDocument {
        try await documentProcessor.correct(data: data, quad: quad)
    }

    func correctionInput(for page: PageRecord) async throws -> CorrectionInput {
        guard let repository else { throw AppFailure.storageUnavailable }
        let url = try await repository.assetURL(id: page.baseAssetID)
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        let correctedID = page.selectedCorrectedAssetID
        let asset = if let correctedID { await repository.asset(id: correctedID) } else { nil as AssetRecord? }
        return CorrectionInput(data: data, initialQuad: asset?.correctionRecipe?.quad)
    }

    func saveCorrection(_ correction: CorrectedDocument, for pageID: UUID) async throws {
        guard let repository else { throw AppFailure.storageUnavailable }
        _ = try await repository.saveCorrection(correction, for: pageID)
        do { try await reconcileQueue() }
        catch { notice = "校正图已保存在本机，备份队列将在下次启动时重建。" }
        await recognize(pageID: pageID)
    }

    func recognize(pageID: UUID) async {
        guard let repository, !recognizingPageIDs.contains(pageID), let page = await repository.page(id: pageID) else { return }
        recognizingPageIDs.insert(pageID)
        defer { recognizingPageIDs.remove(pageID) }
        let sourceID = page.selectedCorrectedAssetID ?? page.baseAssetID
        do {
            let url = try await repository.assetURL(id: sourceID)
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            let result = try await ocrService.recognize(data: data)
            try await repository.saveOCR(result: result, for: pageID, sourceAssetID: sourceID)
        } catch {
            let state: OCRState = error is OCRServiceError ? .unsupported : .failed
            do {
                try await repository.saveOCRFailure(state: state, message: error.localizedDescription, for: pageID, sourceAssetID: sourceID)
            } catch { notice = "页面已保存，但识别结果暂未写入。可在阅读页重新识别。" }
        }
    }

    func searchRecords(for pageID: UUID) async -> [SearchRecord] {
        await repository?.searchRecords(for: pageID) ?? []
    }

    func searchPages(query: String, in journalID: UUID) async -> [PageRecord] {
        await repository?.searchPages(query: query, in: journalID) ?? []
    }

    func saveTags(_ text: String, for pageID: UUID) async throws {
        guard let repository else { throw AppFailure.storageUnavailable }
        try await repository.saveTags(Self.parseTags(text), for: pageID)
    }

    func saveReference(_ text: String, for pageID: UUID) async throws {
        guard let repository else { throw AppFailure.storageUnavailable }
        try await repository.saveOCRReference(text, for: pageID)
    }

    static func parseTags(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
    }

    private func reload() async {
        if let repository { journals = await repository.journals() }
    }

    private func reconcileQueue() async throws {
        guard let repository, let backupQueue else { return }
        for asset in await repository.assetsAwaitingBackup() {
            let priority: SyncPriority = asset.kind == .original ? .original : .derivative
            _ = try await backupQueue.enqueue(SyncJob(entityType: .asset, entityID: asset.id, priority: priority))
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

struct CorrectionInput: Identifiable {
    let id = UUID()
    let data: Data
    let initialQuad: DocumentQuad?
}

enum ArchiveTheme {
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let forest = Color(red: 0.22, green: 0.32, blue: 0.29)
}
