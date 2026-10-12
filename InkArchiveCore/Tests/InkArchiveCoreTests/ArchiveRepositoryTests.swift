import Foundation
import XCTest
@testable import InkArchiveCore

final class ArchiveRepositoryTests: XCTestCase {
    func testOriginalAssetIsDeduplicatedAndPersistsAcrossRelaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try ArchiveRepository(rootDirectory: root)
        let first = try await repository.importOriginal(data: Data("scan".utf8), fileExtension: "jpg", role: .pageFront)
        let second = try await repository.importOriginal(data: Data("scan".utf8), fileExtension: "jpg", role: .pageFront)
        XCTAssertEqual(first.id, second.id)

        let journal = try await repository.createJournal(title: "2026 日常")
        let page = try await repository.addPage(to: journal.id, baseAssetID: first.id)
        XCTAssertEqual(page.baseAssetID, first.id)

        let reopened = try ArchiveRepository(rootDirectory: root)
        let restoredPage = await reopened.page(id: page.id)
        XCTAssertEqual(restoredPage?.baseAssetID, first.id)
    }

    func testLiftLayerRequiresHingeEdge() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try ArchiveRepository(rootDirectory: root)
        let asset = try await repository.importOriginal(data: Data("scan".utf8), fileExtension: "jpg", role: .pageFront)
        let journal = try await repository.createJournal(title: "旅行")
        let page = try await repository.addPage(to: journal.id, baseAssetID: asset.id)

        do {
            _ = try await repository.addLayer(
                to: page.id,
                frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                interaction: .lift
            )
            XCTFail("可翻起物件应要求固定边")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .invalidLayer("可翻起物件必须指定固定边。"))
        }
    }

    func testCaptureCommitsPageCoverAndOriginalAcrossRelaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let journal = try await repository.createJournal(title: "纸上记忆")
        let page = try await repository.importPage(data: Data("original camera data".utf8), fileExtension: "jpg", into: journal.id)
        let reopened = try ArchiveRepository(rootDirectory: root)
        let restoredJournals = await reopened.journals()
        let restoredPages = await reopened.pages(in: journal.id)
        XCTAssertEqual(restoredJournals.first?.coverAssetID, page.baseAssetID)
        XCTAssertEqual(restoredJournals.first?.pageOrder, [page.id])
        XCTAssertEqual(restoredPages.map(\.id), [page.id])
        let file = try await reopened.assetURL(id: page.baseAssetID)
        XCTAssertEqual(try Data(contentsOf: file), Data("original camera data".utf8))
    }

    func testFailedMetadataWriteDoesNotChangeInMemoryArchive() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        // A directory at the metadata file path forces atomic file writing to fail.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ArchiveStore.json"), withIntermediateDirectories: true)
        do {
            _ = try await repository.createJournal(title: "不应提交")
            XCTFail("写入应失败")
        } catch {
            let journals = await repository.journals()
            XCTAssertTrue(journals.isEmpty)
        }
    }

    func testMissingJournalRejectsCaptureBeforeWritingImage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        do {
            _ = try await repository.importPage(data: Data("scan".utf8), fileExtension: "jpg", into: UUID())
            XCTFail("不存在的手账应拒绝保存")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .journalNotFound)
        }
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Assets/originals"), includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty)
    }

    func testDuplicateBytesPreserveDistinctCaptureRoles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let data = Data("same bytes".utf8)
        let pageFront = try await repository.importOriginal(data: data, fileExtension: "jpg", role: .pageFront)
        let layerBack = try await repository.importOriginal(data: data, fileExtension: "jpg", role: .layerBack)
        XCTAssertNotEqual(pageFront.id, layerBack.id)
        XCTAssertEqual(pageFront.relativePath, layerBack.relativePath)
        XCTAssertEqual(layerBack.role, .layerBack)
    }

    func testCorruptStoredOriginalIsNotOverwritten() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let original = Data("scan".utf8)
        let asset = try await repository.importOriginal(data: original, fileExtension: "jpg", role: .pageFront)
        let file = try await repository.assetURL(id: asset.id)
        try Data("corrupt".utf8).write(to: file)
        do {
            _ = try await repository.importOriginal(data: original, fileExtension: "jpg", role: .pageFront)
            XCTFail("应检测到原件损坏")
        } catch let error as ArchiveError {
            guard case .invalidAsset = error else { return XCTFail("错误类型不符") }
        }
        XCTAssertEqual(try Data(contentsOf: file), Data("corrupt".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
