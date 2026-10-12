import Foundation
import XCTest
@testable import InkArchiveCore

final class CorrectionAndOCRTests: XCTestCase {
    func testFourCornersRejectCrossingTinyAndNonFiniteSelection() {
        XCTAssertTrue(DocumentQuad.fullImage.isValid)
        var crossed = DocumentQuad.fullImage
        crossed.setCorner(1, to: .init(x: 0, y: 1))
        XCTAssertFalse(crossed.isValid)
        var tiny = DocumentQuad.fullImage
        tiny.topRight = .init(x: 0.01, y: 0)
        tiny.bottomRight = .init(x: 0.01, y: 0.01)
        tiny.bottomLeft = .init(x: 0, y: 0.01)
        XCTAssertFalse(tiny.isValid)
        var invalid = DocumentQuad.fullImage
        invalid.topLeft = .init(x: .nan, y: 0)
        XCTAssertFalse(invalid.isValid)
    }

    func testCorrectionsCreateVersionsWithoutChangingOriginal() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let journal = try await repository.createJournal(title: "校正测试")
        let original = Data("original".utf8)
        let page = try await repository.importPage(data: original, fileExtension: "jpg", into: journal.id, correction: correction())
        let second = try await repository.saveCorrection(correction(), for: page.id)
        XCTAssertEqual(second.correctedAssetIDs?.count, 2)
        XCTAssertNotEqual(page.selectedCorrectedAssetID, second.selectedCorrectedAssetID)
        let correctedID = try XCTUnwrap(second.selectedCorrectedAssetID)
        let asset = await repository.asset(id: correctedID)
        XCTAssertEqual(asset?.sourceAssetID, page.baseAssetID)
        XCTAssertEqual(asset?.correctionRecipe?.quad, .fullImage)
        let originalURL = try await repository.assetURL(id: page.baseAssetID)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        let reopened = try ArchiveRepository(rootDirectory: root)
        let restored = await reopened.page(id: page.id)
        XCTAssertEqual(restored?.correctedAssetIDs, second.correctedAssetIDs)
    }

    func testOCRCoordinatesPersistAndTagsSurviveEmptyRecognition() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let journal = try await repository.createJournal(title: "检索测试")
        let page = try await repository.importPage(data: Data("original".utf8), fileExtension: "jpg", into: journal.id,
                                                   tags: ["旅行", "  人工标签  ", "旅行"])
        let box = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1)
        let result = OCRResult(lines: [.init(text: "今天去旅行", box: box, confidence: 0.8)], engineRevision: "test", elapsedMilliseconds: 15)
        try await repository.saveOCR(result: result, for: page.id, sourceAssetID: page.baseAssetID)
        let records = await repository.searchRecords(for: page.id)
        XCTAssertEqual(records.first?.boxes, [box])
        XCTAssertEqual(records.first?.confidence, 0.8)
        let matches = await repository.searchPages(query: "今天", in: journal.id)
        XCTAssertEqual(matches.map(\.id), [page.id])
        try await repository.saveOCR(result: .init(lines: [], engineRevision: "test", elapsedMilliseconds: 5), for: page.id, sourceAssetID: page.baseAssetID)
        let reopened = try ArchiveRepository(rootDirectory: root)
        let restored = await reopened.page(id: page.id)
        XCTAssertEqual(restored?.ocrRun?.state, .noText)
        XCTAssertEqual(restored?.tags, ["旅行", "人工标签"])
        let manualMatches = await reopened.searchPages(query: "人工标签", in: journal.id)
        XCTAssertEqual(manualMatches.map(\.id), [page.id])
    }

    func testStaleOCRCannotIndexANewCorrectionVersion() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArchiveRepository(rootDirectory: root)
        let journal = try await repository.createJournal(title: "版本测试")
        let page = try await repository.importPage(data: Data("original".utf8), fileExtension: "jpg", into: journal.id)
        _ = try await repository.saveCorrection(correction(), for: page.id)
        do {
            try await repository.saveOCR(result: .init(lines: [], engineRevision: "test", elapsedMilliseconds: 0), for: page.id, sourceAssetID: page.baseAssetID)
            XCTFail("旧图片识别结果应被拒绝")
        } catch let error as ArchiveError {
            guard case .invalidAsset = error else { return XCTFail("错误类型不符") }
        }
        let records = await repository.searchRecords(for: page.id)
        XCTAssertTrue(records.isEmpty)
    }

    func testLegacyPageAndAssetDecodeWithoutNewFields() throws {
        let page = PageRecord(journalID: UUID(), baseAssetID: UUID(), kind: .normal)
        let decoded = try JSONDecoder().decode(PageRecord.self, from: JSONEncoder().encode(page))
        XCTAssertNil(decoded.correctedAssetIDs)
        XCTAssertNil(decoded.tags)
        let asset = AssetRecord(contentHash: "hash", kind: .original, role: .pageFront, relativePath: "file.jpg", byteCount: 1)
        let restored = try JSONDecoder().decode(AssetRecord.self, from: JSONEncoder().encode(asset))
        XCTAssertNil(restored.correctionRecipe)
    }

    func testCharacterErrorRateTreatsWhitespaceAndEditsCorrectly() {
        XCTAssertEqual(OCRAccuracy(reference: "今天 天气好", recognized: "今天\n天气好").characterErrorRate, 0)
        let wrong = OCRAccuracy(reference: "今天很好", recognized: "今天很坏")
        XCTAssertEqual(wrong.editDistance, 1)
        XCTAssertEqual(wrong.characterErrorRate, 0.25)
        XCTAssertNil(OCRAccuracy(reference: " ", recognized: "文字").characterErrorRate)
        XCTAssertEqual(OCRAccuracy(reference: "手账", recognized: "").characterErrorRate, 1)
    }

    private func correction() -> CorrectedDocument {
        .init(data: Data("derived".utf8), pixelWidth: 100, pixelHeight: 200, recipe: .init(quad: .fullImage))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
