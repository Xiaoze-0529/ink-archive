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
    public func importPage(data: Data, fileExtension: String, into journalID: UUID, at date: Date = .now) throws -> PageRecord {
        guard var journal = snapshot.journals[journalID], journal.deletedAt == nil else {
            throw ArchiveError.journalNotFound
        }
        let imported = try assetStore.importOriginal(data: data, fileExtension: fileExtension, role: .pageFront, captureAt: date)
        let asset = snapshot.assets.values.first {
            $0.contentHash == imported.contentHash && $0.role == .pageFront && $0.kind == .original && $0.deletedAt == nil
        } ?? imported
        let page = PageRecord(journalID: journalID, baseAssetID: asset.id, kind: .normal, createdAt: date)
        var next = snapshot
        next.assets[asset.id] = asset
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
}
