import Foundation

public enum SyncEntityType: String, Codable, Sendable {
    case metadata
    case asset
    case tombstone
}

public enum SyncPriority: Int, Codable, Comparable, Sendable {
    case original = 0
    case metadata = 1
    case derivative = 2
    case thumbnail = 3

    public static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SyncJobState: String, Codable, Sendable {
    case waiting
    case running
    case completed
    case retryNeeded
    case blocked
}

public struct SyncJob: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let entityType: SyncEntityType
    public let entityID: UUID
    public let dependencyIDs: [UUID]
    public let priority: SyncPriority
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastErrorCode: String?
    public var state: SyncJobState

    public init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityID: UUID,
        dependencyIDs: [UUID] = [],
        priority: SyncPriority,
        nextAttemptAt: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.dependencyIDs = dependencyIDs
        self.priority = priority
        self.attemptCount = 0
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = nil
        self.state = .waiting
    }
}

public actor BackupQueue {
    private let storageURL: URL
    private var jobs: [UUID: SyncJob]

    public init(storageURL: URL) throws {
        self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            self.jobs = try JSONDecoder().decode([UUID: SyncJob].self, from: Data(contentsOf: storageURL))
        } else {
            self.jobs = [:]
        }
        // An interrupted process cannot still own a running task.
        var recovered = self.jobs
        for (id, job) in self.jobs where job.state == .running {
            var reset = job
            reset.state = .waiting
            recovered[id] = reset
        }
        if recovered != self.jobs {
            try JSONEncoder().encode(recovered).write(to: storageURL, options: .atomic)
            self.jobs = recovered
        }
    }

    @discardableResult
    public func enqueue(_ job: SyncJob) throws -> SyncJob {
        if let existing = jobs.values.first(where: {
            $0.entityType == job.entityType && $0.entityID == job.entityID && $0.state != .completed
        }) { return existing }
        var next = jobs
        next[job.id] = job
        try commit(next)
        return job
    }

    public func nextReadyJob(at date: Date = .now) -> SyncJob? {
        jobs.values
            .filter { ($0.state == .waiting || $0.state == .retryNeeded) && $0.nextAttemptAt <= date }
            .filter { job in job.dependencyIDs.allSatisfy { jobs[$0]?.state == .completed } }
            .sorted {
                $0.priority == $1.priority
                    ? $0.nextAttemptAt < $1.nextAttemptAt
                    : $0.priority < $1.priority
            }
            .first
    }

    public func markRunning(_ jobID: UUID) throws {
        try update(jobID) { $0.state = .running }
    }

    public func markCompleted(_ jobID: UUID) throws {
        try update(jobID) { $0.state = .completed }
    }

    public func markRetry(_ jobID: UUID, errorCode: String, retryAt: Date) throws {
        try update(jobID) {
            $0.state = .retryNeeded
            $0.attemptCount += 1
            $0.lastErrorCode = errorCode
            $0.nextAttemptAt = retryAt
        }
    }

    private func update(_ jobID: UUID, mutate: (inout SyncJob) -> Void) throws {
        guard var job = jobs[jobID] else { return }
        mutate(&job)
        var next = jobs
        next[jobID] = job
        try commit(next)
    }

    public func pendingCount() -> Int {
        jobs.values.filter { $0.state != .completed }.count
    }

    private func commit(_ next: [UUID: SyncJob]) throws {
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(next)
        try data.write(to: storageURL, options: .atomic)
        jobs = next
    }
}
