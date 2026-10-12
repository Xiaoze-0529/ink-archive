import Foundation
import XCTest
@testable import InkArchiveCore

final class BackupQueueTests: XCTestCase {
    func testInterruptedJobRecoversAndReenqueueIsIdempotent() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = try BackupQueue(storageURL: file)
        let entityID = UUID()
        let job = try await queue.enqueue(SyncJob(entityType: .asset, entityID: entityID, priority: .original))
        try await queue.markRunning(job.id)
        let reopened = try BackupQueue(storageURL: file)
        let recovered = await reopened.nextReadyJob()
        XCTAssertEqual(recovered?.id, job.id)
        XCTAssertEqual(recovered?.state, .waiting)
        let duplicate = try await reopened.enqueue(SyncJob(entityType: .asset, entityID: entityID, priority: .original))
        XCTAssertEqual(duplicate.id, job.id)
        let count = await reopened.pendingCount()
        XCTAssertEqual(count, 1)
    }

    func testDependenciesBlockAssetUntilMetadataCompletes() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = try BackupQueue(storageURL: file)
        let metadata = try await queue.enqueue(SyncJob(entityType: .metadata, entityID: UUID(), priority: .metadata))
        let asset = try await queue.enqueue(SyncJob(entityType: .asset, entityID: UUID(), dependencyIDs: [metadata.id], priority: .original))
        let first = await queue.nextReadyJob()
        XCTAssertEqual(first?.id, metadata.id)
        try await queue.markCompleted(metadata.id)
        let next = await queue.nextReadyJob()
        XCTAssertEqual(next?.id, asset.id)
    }

    func testOriginalAssetsRunBeforeDerivedAssets() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let queue = try BackupQueue(storageURL: file)
        let derived = try await queue.enqueue(SyncJob(entityType: .asset, entityID: UUID(), priority: .derivative))
        let original = try await queue.enqueue(SyncJob(entityType: .asset, entityID: UUID(), priority: .original))

        XCTAssertNotEqual(derived.id, original.id)
        let next = await queue.nextReadyJob()
        XCTAssertEqual(next?.id, original.id)
    }
}
