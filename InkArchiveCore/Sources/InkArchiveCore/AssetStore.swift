import CryptoKit
import Foundation

public struct AssetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try FileManager.default.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: derivedDirectory, withIntermediateDirectories: true)
    }

    public var originalsDirectory: URL {
        rootDirectory.appendingPathComponent("Assets/originals", isDirectory: true)
    }

    public var derivedDirectory: URL {
        rootDirectory.appendingPathComponent("Assets/derived", isDirectory: true)
    }

    public static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func importOriginal(
        data: Data,
        fileExtension: String,
        role: AssetRole,
        captureAt: Date = .now
    ) throws -> AssetRecord {
        let hash = Self.contentHash(for: data)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !data.isEmpty, ["jpg", "jpeg", "heic", "heif", "png", "tiff"].contains(normalizedExtension) else {
            throw ArchiveError.invalidAsset("文件为空或不是支持的图片格式。")
        }
        let filename = "\(hash).\(normalizedExtension)"
        let destination = originalsDirectory.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: destination.path) {
            let temporary = originalsDirectory.appendingPathComponent(".\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } else if Self.contentHash(for: try Data(contentsOf: destination)) != hash {
            throw ArchiveError.invalidAsset("已存原件校验失败，未覆盖原文件。")
        }

        return AssetRecord(
            contentHash: hash,
            kind: .original,
            role: role,
            relativePath: "Assets/originals/\(filename)",
            byteCount: data.count,
            captureAt: captureAt
        )
    }

    public func url(for asset: AssetRecord) -> URL {
        rootDirectory.appendingPathComponent(asset.relativePath)
    }

    public func saveCorrection(_ document: CorrectedDocument, source: AssetRecord) throws -> AssetRecord {
        guard source.kind == .original, !document.data.isEmpty, document.recipe.quad.isValid,
              document.pixelWidth > 0, document.pixelHeight > 0 else {
            throw ArchiveError.invalidAsset("校正必须关联有效原件与四角参数。")
        }
        let id = UUID()
        let relativePath = "Assets/derived/\(source.id.uuidString)/\(id.uuidString).jpg"
        let file = rootDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document.data.write(to: file, options: .atomic)
        return AssetRecord(
            id: id, contentHash: Self.contentHash(for: document.data), kind: .corrected, role: source.role,
            sourceAssetID: source.id, relativePath: relativePath, byteCount: document.data.count,
            captureAt: source.captureAt, pixelWidth: document.pixelWidth, pixelHeight: document.pixelHeight,
            correctionRecipe: document.recipe
        )
    }
}
