//
//  SyncServiceTests.swift
//  TackleTests
//
//  The push loop and the merge gate, against a real store and a fake server.
//

import Foundation
import Testing
@testable import Tackle

@Suite("Sync service", .serialized)
struct SyncServiceTests {

    private func task(_ title: String, _ sortIndex: Double = 1024) -> TaskItem {
        TaskItem(title: title, status: .todo, sortIndex: sortIndex)
    }

    private func service(
        local: CoreDataStore,
        remote: FakeRemote,
        monitor: FakeMonitor = FakeMonitor()
    ) -> SyncService {
        SyncService(local: local, remote: remote, monitor: monitor)
    }

    // MARK: - Pushing

    @Test("A pass pushes everything queued and empties the outbox")
    func pushDrainsTheOutbox() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let first = task("a")
        let second = task("b", 2048)
        try await store.save(first)
        try await store.save(second)

        await service(local: store, remote: remote).pushPending()

        #expect(Set(remote.pushedIds) == [first.id, second.id])
        let pending = try await store.pendingTaskIds()
        #expect(pending.isEmpty)
    }

    /// The offline case. Losing the row would lose the edit, so a failure has to leave it.
    @Test("A failed push leaves its outbox row in place")
    func failedPushKeepsTheRow() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        remote.failEveryPush()
        let item = task("a")
        try await store.save(item)

        await service(local: store, remote: remote).pushPending()

        #expect(remote.pushed.isEmpty)
        let pending = try await store.pendingTaskIds()
        #expect(pending == [item.id])
    }

    @Test("A failed push stops the pass rather than working through the queue")
    func failureStopsThePass() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        remote.failEveryPush()
        try await store.save(task("a"))
        try await store.save(task("b", 2048))

        await service(local: store, remote: remote).pushPending()

        // Offline is offline; there is no point attempting the rest of the queue.
        #expect(remote.pushed.isEmpty)
        let pending = try await store.pendingTaskIds()
        #expect(pending.count == 2)
    }

    /// The bug this guards: the push succeeds, we clear the row, and the edit the user made
    /// while it was in flight is never sent.
    @Test("An edit made during a push keeps the task queued")
    func editDuringPushStaysQueued() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let original = task("original")
        try await store.save(original)

        remote.duringPush = { _ in
            var edited = original
            edited.title = "edited mid-flight"
            edited.updatedAt = original.updatedAt.addingTimeInterval(1)
            try? await store.save(edited)
        }

        await service(local: store, remote: remote).pushPending()

        #expect(remote.pushed.count == 1)
        let pending = try await store.pendingTaskIds()
        #expect(pending == [original.id], "the newer edit still has to go out")

        let stored = try await store.task(id: original.id)
        #expect(stored?.title == "edited mid-flight")
    }

    @Test("A task whose row outlived it is dropped from the outbox")
    func missingTaskClearsItsRow() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let item = task("a")
        try await store.save(item)
        // A merge can delete the task out from under a queued row.
        var tombstone = item
        tombstone.isDeleted = true
        tombstone.updatedAt = item.updatedAt.addingTimeInterval(1)
        try await store.mergeRemote([tombstone])

        await service(local: store, remote: remote).pushPending()

        #expect(remote.pushed.isEmpty)
        let pending = try await store.pendingPushes()
        #expect(pending.isEmpty)
    }

    /// Actors are reentrant, so isolation alone does not stop two passes overlapping — the
    /// service carries a flag for it. Without it, a task gets pushed twice.
    @Test("Two passes at once push each task exactly once")
    func concurrentPassesDoNotDuplicate() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let first = task("a")
        let second = task("b", 2048)
        try await store.save(first)
        try await store.save(second)
        // Widen the window so the second pass is guaranteed to start mid-push.
        remote.duringPush = { _ in try? await Task.sleep(for: .milliseconds(20)) }

        let sync = service(local: store, remote: remote)
        async let one: Void = sync.pushPending()
        async let two: Void = sync.pushPending()
        _ = await (one, two)

        #expect(remote.pushedIds.count == 2)
        #expect(Set(remote.pushedIds) == [first.id, second.id])
    }

    // MARK: - Merging

    @Test("A remote change with nothing queued is applied")
    func mergeAppliesRemoteChanges() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let sync = service(local: store, remote: remote)
        await sync.start()

        let incoming = task("from the server")
        remote.emit([incoming])

        let arrived = await eventually {
            let stored = try? await store.task(id: incoming.id)
            return stored?.title == "from the server"
        }
        #expect(arrived)

        await sync.stop()
    }

    /// Push before pull. A queued local edit must not be overwritten by the server's copy of
    /// the same task, whenever the listener happens to fire.
    @Test("A remote change is ignored while that task is still queued")
    @MainActor
    func mergeSkipsQueuedTasks() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        // Nothing can drain, so the row stays queued for the whole test.
        remote.failEveryPush()
        let local = task("local edit")
        try await store.save(local)

        let status = SyncStatus()
        let sync = SyncService(local: store, remote: remote, monitor: FakeMonitor(), status: status)
        await sync.start()

        var incoming = local
        incoming.title = "server copy"
        incoming.updatedAt = local.updatedAt.addingTimeInterval(60)
        remote.emit([incoming])

        // `hasLoadedRemote` flips at the top of the merge, so this waits for the merge to have
        // actually run rather than sleeping and hoping.
        let merged = await eventually { await MainActor.run { status.hasLoadedRemote } }
        #expect(merged)

        let stored = try await store.task(id: local.id)
        #expect(stored?.title == "local edit")

        await sync.stop()
    }

    // MARK: - Connectivity

    @Test("Connectivity returning drains what piled up while offline")
    func comingOnlinePushes() async throws {
        let store = makeStore()
        let remote = FakeRemote()
        let monitor = FakeMonitor(isOnline: false)
        remote.failEveryPush()
        let item = task("a")
        try await store.save(item)

        let sync = SyncService(local: store, remote: remote, monitor: monitor)
        await sync.start()

        // The pass `start()` kicks off fails, so the row is still waiting.
        let queued = await eventually {
            let pending = try? await store.pendingTaskIds()
            return pending?.contains(item.id) == true
        }
        #expect(queued)

        remote.stopFailing()
        monitor.set(online: true)

        let drained = await eventually {
            let pending = try? await store.pendingTaskIds()
            return pending?.isEmpty == true
        }
        #expect(drained)
        #expect(remote.pushedIds == [item.id])

        await sync.stop()
    }
}
