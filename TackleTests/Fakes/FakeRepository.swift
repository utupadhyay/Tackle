//
//  FakeRepository.swift
//  TackleTests
//
//  What the view models see instead of Core Data.
//

import Foundation
import Synchronization
@testable import Tackle

/// Records the calls a view model makes, and hands back a fixed set of tasks to display.
final class FakeRepository: TaskRepositoryProtocol, @unchecked Sendable {
    struct Creation: Sendable, Equatable {
        let title: String
        let details: String
        let status: TaskStatus
    }

    struct Refused: Error {}

    private struct State {
        var seed: [TaskItem] = []
        var created: Creation?
        var updated: TaskItem?
        var deleted: UUID?
        var syncCount = 0
        var refuses = false
    }

    private let state = Mutex(State())

    init(seed: [TaskItem] = [], refuses: Bool = false) {
        state.withLock {
            $0.seed = seed
            $0.refuses = refuses
        }
    }

    var created: Creation? { state.withLock { $0.created } }
    var updated: TaskItem? { state.withLock { $0.updated } }
    var deleted: UUID? { state.withLock { $0.deleted } }
    var syncCount: Int { state.withLock { $0.syncCount } }

    private func failIfRefusing() throws {
        if state.withLock({ $0.refuses }) { throw Refused() }
    }

    var tasks: AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            continuation.yield(state.withLock { $0.seed })
            continuation.finish()
        }
    }

    func create(title: String, details: String, status: TaskStatus) async throws {
        try failIfRefusing()
        state.withLock { $0.created = Creation(title: title, details: details, status: status) }
    }

    func update(_ task: TaskItem) async throws {
        try failIfRefusing()
        state.withLock { $0.updated = task }
    }

    func delete(_ id: UUID) async throws {
        try failIfRefusing()
        state.withLock { $0.deleted = id }
    }

    func changeStatus(_ id: UUID, to status: TaskStatus) async throws {
        try failIfRefusing()
    }

    func move(_ id: UUID, to status: TaskStatus, above: UUID?, below: UUID?) async throws {
        try failIfRefusing()
    }
    func sync() async {
        state.withLock { $0.syncCount += 1 }
    }
}
