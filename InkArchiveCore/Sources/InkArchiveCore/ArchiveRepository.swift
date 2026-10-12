import Foundation

public actor ArchiveRepository {
    private let databaseURL: URL
    private let assetStore: AssetStore
    private var snapshot: ArchiveSnapshot

    public init(rootDirectory: URL) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        self.databaseURL = rootDirectory.appendingPathComponent("ArchiveStore.json")
        self.assetStore = try AssetStore(rootDirectory: rootDirectory)

        if FileManager.default.fileExists(atPath: databaseURL.path) {
            let data = try Data(contentsOf: databaseURL)
            self.snapshot = try JSONDecoder().decode(ArchiveSnapshot.self, from: data)
        } else {
            self.snapshot = ArchiveSnapshot()
        }
    }

    @discardableResult
    public func createJournal(title: String, at date: Date = .now) throws -> JournalRecord {
        let journal = JournalRecord(title: title, createdAt: date)
        var next = snapshot
        next.journals[journal.id] = journal
        try commit(next)
        return journal
    }

    public func journals() -> [JournalRecord] {
        snapshot.journals.values.filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func importOriginal(
        data: Data,
        fileExtension: String,
        role: AssetRole,
        captureAt: Date = .now
    ) throws -> AssetRecord {
        let hash = AssetStore.contentHash(for: data)
        // Verify or restore the file even when its record already exists.
        let asset = try assetStore.importOriginal(
            data: data,
            fileExtension: fileExtension,
            role: role,
            captureAt: captureAt
        )
        if let existing = snapshot.assets.values.first(where: { $0.contentHash == hash && $0.role == role && $0.kind == .original && $0.deletedAt == nil }) {
            return existing
        }
        var next = snapshot
        next.assets[asset.id] = asset
        try commit(next)
        return asset
    }

    @discardableResult
    public func addPage(
        to journalID: UUID,
        baseAssetID: UUID,
        kind: PageKind = .normal,
        at date: Date = .now
    ) throws -> PageRecord {
        guard var journal = snapshot.journals[journalID], journal.deletedAt == nil else {
            throw ArchiveError.journalNotFound
        }
        guard let asset = snapshot.assets[baseAssetID], asset.kind == .original, asset.role == .pageFront, asset.deletedAt == nil else {
            throw ArchiveError.assetMustBeOriginal
        }

        let page = PageRecord(journalID: journalID, baseAssetID: baseAssetID, kind: kind, createdAt: date)
        var next = snapshot
        next.pages[page.id] = page
        journal.pageOrder.append(page.id)
        journal.revision += 1
        journal.updatedAt = date
        next.journals[journal.id] = journal
        try commit(next)
        return page
    }

    @discardableResult
    public func addLayer(
        to pageID: UUID,
        frame: NormalizedRect,
        interaction: LayerInteraction,
        hingeEdge: HingeEdge? = nil,
        frontAssetID: UUID? = nil,
        at date: Date = .now
    ) throws -> LayerRecord {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else {
            throw ArchiveError.pageNotFound
        }
        guard (0...1).contains(frame.x), (0...1).contains(frame.y), frame.width > 0, frame.height > 0,
              frame.x + frame.width <= 1, frame.y + frame.height <= 1 else {
            throw ArchiveError.invalidLayer("物件层坐标必须位于页面范围内。")
        }
        if interaction == .lift && hingeEdge == nil {
            throw ArchiveError.invalidLayer("可翻起物件必须指定固定边。")
        }
        if let frontAssetID, snapshot.assets[frontAssetID] == nil {
            throw ArchiveError.assetNotFound
        }

        let layer = LayerRecord(
            pageID: pageID,
            zIndex: page.layerOrder.count,
            frame: frame,
            interaction: interaction,
            hingeEdge: hingeEdge,
            frontAssetID: frontAssetID,
            createdAt: date
        )
        var next = snapshot
        next.layers[layer.id] = layer
        page.layerOrder.append(layer.id)
        page.revision += 1
        page.updatedAt = date
        if interaction != .fixed { page.scanStatus = .needsSupplement }
        next.pages[page.id] = page
        try commit(next)
        return layer
    }

    public func page(id: UUID) -> PageRecord? {
        snapshot.pages[id]
    }

    public func asset(id: UUID) -> AssetRecord? {
        snapshot.assets[id]
    }

    public func updateBackupState(for assetID: UUID, to state: BackupState) throws {
        guard var asset = snapshot.assets[assetID] else { throw ArchiveError.assetNotFound }
        asset.backupState = state
        var next = snapshot
        next.assets[assetID] = asset
        try commit(next)
    }

    /// Commits a camera capture and its page in one metadata write.
    @discardableResult
    public func importPage(data: Data, fileExtension: String, into journalID: UUID,
                           correction: CorrectedDocument? = nil, tags: [String] = [], at date: Date = .now) throws -> PageRecord {
        guard var journal = snapshot.journals[journalID], journal.deletedAt == nil else {
            throw ArchiveError.journalNotFound
        }
        let imported = try assetStore.importOriginal(data: data, fileExtension: fileExtension, role: .pageFront, captureAt: date)
        let asset = snapshot.assets.values.first {
            $0.contentHash == imported.contentHash && $0.role == .pageFront && $0.kind == .original && $0.deletedAt == nil
        } ?? imported
        var page = PageRecord(journalID: journalID, baseAssetID: asset.id, kind: .normal, createdAt: date)
        page.tags = normalizedTags(tags)
        var next = snapshot
        next.assets[asset.id] = asset
        if let correction {
            let corrected = try assetStore.saveCorrection(correction, source: asset)
            next.assets[corrected.id] = corrected
            page.correctedAssetIDs = [corrected.id]
            page.selectedCorrectedAssetID = corrected.id
        }
        next.pages[page.id] = page
        journal.pageOrder.append(page.id)
        journal.revision += 1
        journal.updatedAt = date
        if journal.coverAssetID == nil { journal.coverAssetID = asset.id }
        next.journals[journalID] = journal
        try commit(next)
        return page
    }

    public func pages(in journalID: UUID) -> [PageRecord] {
        guard let journal = snapshot.journals[journalID] else { return [] }
        return journal.pageOrder.compactMap { snapshot.pages[$0] }.filter { $0.deletedAt == nil }
    }

    public func originalAssetsAwaitingBackup() -> [AssetRecord] {
        snapshot.assets.values.filter { $0.kind == .original && $0.backupState != .backedUp && $0.deletedAt == nil }
    }

    public func assetsAwaitingBackup() -> [AssetRecord] {
        snapshot.assets.values.filter { $0.backupState != .backedUp && $0.deletedAt == nil }
    }

    @discardableResult
    public func saveCorrection(_ document: CorrectedDocument, for pageID: UUID, at date: Date = .now) throws -> PageRecord {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else { throw ArchiveError.pageNotFound }
        guard let original = snapshot.assets[page.baseAssetID], original.deletedAt == nil else { throw ArchiveError.assetNotFound }
        let corrected = try assetStore.saveCorrection(document, source: original)
        var next = snapshot
        next.assets[corrected.id] = corrected
        page.correctedAssetIDs = (page.correctedAssetIDs ?? []) + [corrected.id]
        page.selectedCorrectedAssetID = corrected.id
        page.ocrRun = nil
        page.revision += 1
        page.updatedAt = date
        next.pages[pageID] = page
        try commit(next)
        return page
    }

    public func saveTags(_ tags: [String], for pageID: UUID) throws {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else { throw ArchiveError.pageNotFound }
        page.tags = normalizedTags(tags)
        page.revision += 1
        page.updatedAt = .now
        var next = snapshot
        next.pages[pageID] = page
        try commit(next)
    }

    public func saveOCR(result: OCRResult, for pageID: UUID, sourceAssetID: UUID) throws {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else { throw ArchiveError.pageNotFound }
        guard sourceAssetID == (page.selectedCorrectedAssetID ?? page.baseAssetID) else {
            throw ArchiveError.invalidAsset("页面校正版本已经改变，请重新识别。")
        }
        var next = snapshot
        next.searchRecords = next.searchRecords.filter {
            !($0.value.ownerType == .page && $0.value.ownerID == pageID && $0.value.sourceAssetID == sourceAssetID)
        }
        for line in result.lines {
            let record = SearchRecord(
                ownerType: .page, ownerID: pageID, text: line.text, language: result.language,
                boxes: [line.box], sourceAssetID: sourceAssetID, engineRevision: result.engineRevision, confidence: line.confidence
            )
            next.searchRecords[record.id] = record
        }
        page.ocrRun = OCRRunRecord(state: result.lines.isEmpty ? .noText : .recognized, sourceAssetID: sourceAssetID,
                                   engineRevision: result.engineRevision, elapsedMilliseconds: result.elapsedMilliseconds)
        next.pages[pageID] = page
        try commit(next)
    }

    public func saveOCRFailure(state: OCRState, message: String, for pageID: UUID, sourceAssetID: UUID) throws {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else { throw ArchiveError.pageNotFound }
        guard sourceAssetID == (page.selectedCorrectedAssetID ?? page.baseAssetID) else {
            throw ArchiveError.invalidAsset("识别失败消息对应旧的图片版本。")
        }
        // Existing successful records remain available after a failed re-run.
        page.ocrRun = OCRRunRecord(state: state, sourceAssetID: sourceAssetID, message: message)
        var next = snapshot
        next.pages[pageID] = page
        try commit(next)
    }

    public func searchRecords(for pageID: UUID, sourceAssetID: UUID? = nil) -> [SearchRecord] {
        guard let page = snapshot.pages[pageID], page.deletedAt == nil else { return [] }
        let source = sourceAssetID ?? page.selectedCorrectedAssetID ?? page.baseAssetID
        return snapshot.searchRecords.values.filter {
            $0.ownerType == .page && $0.ownerID == pageID && $0.sourceAssetID == source
        }.sorted {
            let left = $0.boxes.first ?? .init(x: 0, y: 0, width: 0, height: 0)
            let right = $1.boxes.first ?? .init(x: 0, y: 0, width: 0, height: 0)
            let leftRow = Int(left.y * 100), rightRow = Int(right.y * 100)
            if leftRow != rightRow { return leftRow < rightRow }
            return left.x < right.x
        }
    }

    public func searchPages(query: String, in journalID: UUID) -> [PageRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pages = pages(in: journalID)
        guard !query.isEmpty else { return pages }
        return pages.filter { page in
            (page.tags ?? []).contains { $0.localizedCaseInsensitiveContains(query) } ||
            searchRecords(for: page.id).map(\.text).joined(separator: "\n").localizedCaseInsensitiveContains(query)
        }
    }

    public func saveOCRReference(_ text: String, for pageID: UUID) throws {
        guard var page = snapshot.pages[pageID], page.deletedAt == nil else { throw ArchiveError.pageNotFound }
        page.ocrReferenceText = text
        var next = snapshot
        next.pages[pageID] = page
        try commit(next)
    }

    public func assetURL(id: UUID) throws -> URL {
        guard let asset = snapshot.assets[id], asset.deletedAt == nil else { throw ArchiveError.assetNotFound }
        return assetStore.url(for: asset)
    }

    private func commit(_ next: ArchiveSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next)
        try data.write(to: databaseURL, options: .atomic)
        snapshot = next
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
