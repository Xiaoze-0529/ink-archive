import Foundation

public enum PageKind: String, Codable, Sendable {
    case normal
    case spread
    case insert
    case foldout
}

public enum LayerInteraction: String, Codable, Sendable {
    case fixed
    case lift
    case insert
    case foldout
}

public enum HingeEdge: String, Codable, Sendable {
    case top
    case right
    case bottom
    case left
}

public enum AssetKind: String, Codable, Sendable {
    case original
    case corrected
    case enhanced
    case thumbnail
    case export
}

public enum AssetRole: String, Codable, Sendable {
    case pageFront
    case pageBack
    case layerFront
    case layerBack
    case underlay
    case foldoutSegment
}

public enum BackupState: String, Codable, Sendable {
    case localOnly
    case queued
    case uploading
    case backedUp
    case retryNeeded
    case blocked
}

public struct NormalizedRect: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct NormalizedPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct JournalRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var coverAssetID: UUID?
    public var pageOrder: [UUID]
    public var tags: [String]
    public var dateStart: Date?
    public var dateEnd: Date?
    public var revision: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.coverAssetID = nil
        self.pageOrder = []
        self.tags = []
        self.dateStart = nil
        self.dateEnd = nil
        self.revision = 1
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.deletedAt = nil
    }
}

public struct PageRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let journalID: UUID
    public let baseAssetID: UUID
    /// Optional additions preserve decoding of archives created before cropping/OCR support.
    public var correctedAssetIDs: [UUID]?
    public var selectedCorrectedAssetID: UUID?
    public var tags: [String]?
    public var ocrRun: OCRRunRecord?
    public var ocrReferenceText: String?
    public var kind: PageKind
    public var layerOrder: [UUID]
    public var scanStatus: ScanStatus
    public var revision: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public enum ScanStatus: String, Codable, Sendable {
        case complete
        case needsSupplement
        case needsReview
    }

    public init(id: UUID = UUID(), journalID: UUID, baseAssetID: UUID, kind: PageKind, createdAt: Date = .now) {
        self.id = id
        self.journalID = journalID
        self.baseAssetID = baseAssetID
        self.correctedAssetIDs = nil
        self.selectedCorrectedAssetID = nil
        self.tags = nil
        self.ocrRun = nil
        self.ocrReferenceText = nil
        self.kind = kind
        self.layerOrder = []
        self.scanStatus = .needsReview
        self.revision = 1
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.deletedAt = nil
    }
}

public struct LayerRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let pageID: UUID
    public var zIndex: Int
    public var frame: NormalizedRect
    public var mask: [NormalizedPoint]?
    public var interaction: LayerInteraction
    public var hingeEdge: HingeEdge?
    public var frontAssetID: UUID?
    public var backAssetID: UUID?
    public var underlayAssetID: UUID?
    public var linkedPageIDs: [UUID]
    public var revision: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        pageID: UUID,
        zIndex: Int,
        frame: NormalizedRect,
        interaction: LayerInteraction,
        hingeEdge: HingeEdge? = nil,
        frontAssetID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.pageID = pageID
        self.zIndex = zIndex
        self.frame = frame
        self.mask = nil
        self.interaction = interaction
        self.hingeEdge = hingeEdge
        self.frontAssetID = frontAssetID
        self.backAssetID = nil
        self.underlayAssetID = nil
        self.linkedPageIDs = []
        self.revision = 1
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.deletedAt = nil
    }
}

public struct AssetRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let contentHash: String
    public let kind: AssetKind
    public let role: AssetRole
    public let sourceAssetID: UUID?
    public let relativePath: String
    public let byteCount: Int
    public let captureAt: Date
    public let createdAt: Date
    public var backupState: BackupState
    public var deletedAt: Date?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let correctionRecipe: CorrectionRecipe?

    public init(
        id: UUID = UUID(),
        contentHash: String,
        kind: AssetKind,
        role: AssetRole,
        sourceAssetID: UUID? = nil,
        relativePath: String,
        byteCount: Int,
        captureAt: Date = .now,
        createdAt: Date = .now,
        backupState: BackupState = .localOnly,
        pixelWidth: Int? = nil, pixelHeight: Int? = nil, correctionRecipe: CorrectionRecipe? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kind = kind
        self.role = role
        self.sourceAssetID = sourceAssetID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.captureAt = captureAt
        self.createdAt = createdAt
        self.backupState = backupState
        self.deletedAt = nil
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.correctionRecipe = correctionRecipe
    }
}

public struct SearchRecord: Codable, Identifiable, Sendable, Equatable {
    public enum OwnerType: String, Codable, Sendable { case page, layer }

    public let id: UUID
    public let ownerType: OwnerType
    public let ownerID: UUID
    public let text: String
    public let language: String
    public let boxes: [NormalizedRect]
    public let sourceAssetID: UUID
    public let engineRevision: String
    public let createdAt: Date
    public let confidence: Float?

    public init(id: UUID = UUID(), ownerType: OwnerType, ownerID: UUID, text: String, language: String,
                boxes: [NormalizedRect], sourceAssetID: UUID, engineRevision: String, createdAt: Date = .now, confidence: Float? = nil) {
        self.id = id
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.text = text
        self.language = language
        self.boxes = boxes
        self.sourceAssetID = sourceAssetID
        self.engineRevision = engineRevision
        self.createdAt = createdAt
        self.confidence = confidence
    }
}

public struct ArchiveSnapshot: Codable, Sendable {
    public var journals: [UUID: JournalRecord] = [:]
    public var pages: [UUID: PageRecord] = [:]
    public var layers: [UUID: LayerRecord] = [:]
    public var assets: [UUID: AssetRecord] = [:]
    public var searchRecords: [UUID: SearchRecord] = [:]

    public init() {}
}

public enum ArchiveError: Error, Equatable {
    case journalNotFound
    case pageNotFound
    case assetNotFound
    case assetMustBeOriginal
    case invalidAsset(String)
    case invalidLayer(String)
}
