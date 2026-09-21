//
//  SyncFakes.swift
//  TackleTests
//
//  Stand-ins for the two things the sync loop talks to: the server and the network.
//

import Foundation
import Synchronization
@testable import Tackle

struct RemoteUnreachable: Error {}

/// Records what the push loop sent, can be made to fail, and can run work in the middle of a
/// push — which is how the "edited while in flight" case is staged.
final class FakeRemote: RemoteStoreProtocol, @unchecked Sendable {
    private struct State {
        var pushed: [TaskItem] = []
        var failure: (any Error)?
        var continuation: AsyncStream<[TaskItem]>.Continuation?
    }

    private let state = Mutex(State())

    /// Runs inside `push`, before it either succeeds or throws.
    nonisolated(unsafe) var duringPush: (@Sendable (TaskItem) async -> Void)?

    var pushed: [TaskItem] { state.withLock { $0.pushed } }
    var pushedIds: [UUID] { pushed.map(\.id) }

    func failEveryPush() {
        state.withLock { $0.failure = RemoteUnreachable() }
    }

    /// Plays the part of the network coming back.
    func stopFailing() {
        state.withLock { $0.failure = nil }
    }

    func push(_ task: TaskItem) async throws {
        await duringPush?(task)
        if let failure = state.withLock({ $0.failure }) { throw failure }
        state.withLock { $0.pushed.append(task) }
    }

    func remoteChanges() -> AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            state.withLock { $0.continuation = continuation }
        }
    }

    /// Plays the part of a Firestore snapshot arriving.
    func emit(_ tasks: [TaskItem]) {
        state.withLock { $0.continuation }?.yield(tasks)
    }
}

/// Connectivity the test drives by hand.
final class FakeMonitor: NetworkMonitoring, @unchecked Sendable {
    private struct State {
        var isOnline: Bool
        var continuation: AsyncStream<Bool>.Continuation?
    }

    private let state: Mutex<State>

    init(isOnline: Bool = true) {
        state = Mutex(State(isOnline: isOnline))
    }

    var isOnline: Bool {
        get async { state.withLock { $0.isOnline } }
    }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            state.withLock { $0.continuation = continuation }
        }
    }

    func set(online: Bool) {
        let continuation = state.withLock { state -> AsyncStream<Bool>.Continuation? in
            state.isOnline = online
            return state.continuation
        }
        continuation?.yield(online)
    }
}

/// A real store on a throwaway in-memory stack. The outbox rules are most of what the sync
/// loop depends on, so the tests exercise the real thing rather than a fake of it.
func makeStore() -> CoreDataStore {
    CoreDataStore(stack: CoreDataStack(inMemory: true))
}

/// Polls until `condition` holds, so a test never races the background work it triggered.
/// Returns false if it never does, which fails the test rather than hanging it.
@discardableResult
func eventually(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
