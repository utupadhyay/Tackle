//
//  CoreDataStoreTests.swift
//  TackleTests
//
//  The store is the source of truth, so these run against a real Core Data stack on an
//  in-memory store rather than a fake of it.
//

import Foundation
import Testing
@testable import Tackle

@Suite("Core Data store", .serialized)
struct CoreDataStoreTests {

    private func task(
        _ title: String,
        _ status: TaskStatus = .todo,
        _ sortIndex: Double = 1024,
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) -> TaskItem {
        TaskItem(
            title: title,
            status: status,
            sortIndex: sortIndex,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    // MARK: - Outbox

    @Test("Saving a task queues it for push")
    func saveQueuesAPush() async throws {
        let store = makeStore()
        let item = task("a")

        try await store.save(item)

        let pushes = try await store.pendingPushes()
        #expect(pushes.count == 1)
        #expect(pushes.first?.taskId == item.id)
    }

    /// The reason the outbox stores ids and not operations: editing offline five times has to
    /// leave one row, not five.
    @Test("Editing the same task repeatedly still leaves one outbox row")
    func repeatedEditsCoalesce() async throws {
        let store = makeStore()
        var item = task("a")

        for index in 0..<5 {
            item.title = "edit \(index)"
            item.updatedAt = .now
            try await store.save(item)
        }

        let pushes = try await store.pendingPushes()
        #expect(pushes.count == 1)
    }

    @Test("A task is unsynced while queued and synced once the row clears")
    func syncedIsDerivedFromTheOutbox() async throws {
        let store = makeStore()
        let item = task("a")
        try await store.save(item)

        let queued = try await store.task(id: item.id)
        #expect(queued?.isSynced == false)

        let push = try await store.pendingPushes()[0]
        try await store.clearPush(push.id)

        let cleared = try await store.task(id: item.id)
        #expect(cleared?.isSynced == true)
    }

    @Test("Pending ids report every queued task")
    func pendingIds() async throws {
        let store = makeStore()
        let first = task("a")
        let second = task("b", .done, 2048)
        try await store.save(first)
        try await store.save(second)

        let ids = try await store.pendingTaskIds()
        #expect(ids == [first.id, second.id])
    }

    @Test("Marking a push in flight records what was sent")
    func markPushing() async throws {
        let store = makeStore()
        let item = task("a")
        try await store.save(item)
        let push = try await store.pendingPushes()[0]
        #expect(push.pushedUpdatedAt == nil)

        let sentAt = Date.now
        try await store.markPushing(push, updatedAt: sentAt)

        let reloaded = try await store.pendingPushes()[0]
        #expect(reloaded.pushedUpdatedAt != nil)
    }

    // MARK: - Reading

    @Test("Soft-deleted tasks are filtered out of the board but still exist")
    func softDeleteIsHiddenNotGone() async throws {
        let store = makeStore()
        let item = task("a", .todo, 1024, isDeleted: true)
        try await store.save(item)

        let board = try await store.fetchAll()
        #expect(board.isEmpty)

        // Still present, which is what lets the delete be pushed to the server.
        let stored = try await store.task(id: item.id)
        #expect(stored?.isDeleted == true)
    }

    @Test("Reads come back ordered by stage, then by sort index")
    func readsAreOrdered() async throws {
        let store = makeStore()
        try await store.save(task("done", .done, 10))
        try await store.save(task("second todo", .todo, 2048))
        try await store.save(task("in progress", .inProgress, 10))
        try await store.save(task("first todo", .todo, 1024))

        let board = try await store.fetchAll()

        #expect(board.map(\.title) == ["first todo", "second todo", "in progress", "done"])
    }

    @Test("Subscribers get a snapshot as soon as they subscribe")
    func streamYieldsASnapshot() async throws {
        let store = makeStore()
        try await store.save(task("a"))

        var iterator = store.tasks.makeAsyncIterator()
        let snapshot = await iterator.next()

        #expect(snapshot?.count == 1)
    }

    // MARK: - Merging

    @Test("A task only on the server is taken as-is, and is already synced")
    func mergeInsertsUnknownTasks() async throws {
        let store = makeStore()
        let remote = task("from the server")

        try await store.mergeRemote([remote])

        let stored = try await store.task(id: remote.id)
        #expect(stored?.title == "from the server")
        // Nothing queued it, so it isn't waiting to go anywhere.
        #expect(stored?.isSynced == true)
    }

    /// The whole merge rule in one line: newer wins, and "newer" is the server's `updatedAt`
    /// being strictly greater. Equal timestamps are our own write echoing back.
    @Test("A newer remote edit wins")
    func mergeAppliesNewerRemoteEdits() async throws {
        let store = makeStore()
        let local = task("local", .todo, 1024, updatedAt: Date(timeIntervalSince1970: 1_000))
        try await store.save(local)

        var remote = local
        remote.title = "remote"
        remote.updatedAt = Date(timeIntervalSince1970: 2_000)
        try await store.mergeRemote([remote])

        let stored = try await store.task(id: local.id)
        #expect(stored?.title == "remote")
    }

    @Test("An older remote edit is ignored")
    func mergeIgnoresStaleRemoteEdits() async throws {
        let store = makeStore()
        let local = task("local", .todo, 1024, updatedAt: Date(timeIntervalSince1970: 2_000))
        try await store.save(local)

        var remote = local
        remote.title = "stale"
        remote.updatedAt = Date(timeIntervalSince1970: 1_000)
        try await store.mergeRemote([remote])

        let stored = try await store.task(id: local.id)
        #expect(stored?.title == "local")
    }

    @Test("An echo of our own write changes nothing")
    func mergeIgnoresItsOwnEcho() async throws {
        let store = makeStore()
        let local = task("local", .todo, 1024, updatedAt: Date(timeIntervalSince1970: 1_000))
        try await store.save(local)

        // Same timestamp, which is what the server sends straight back after a push.
        try await store.mergeRemote([local])

        let stored = try await store.task(id: local.id)
        #expect(stored?.title == "local")
    }

    @Test("A task deleted on the server is removed locally")
    func mergeDeletes() async throws {
        let store = makeStore()
        let local = task("local")
        try await store.save(local)

        var remote = local
        remote.isDeleted = true
        try await store.mergeRemote([remote])

        let stored = try await store.task(id: local.id)
        #expect(stored == nil)
    }

    @Test("A delete for a task we never had is not resurrected as a row")
    func mergeIgnoresUnknownDeletes() async throws {
        let store = makeStore()

        try await store.mergeRemote([task("never seen", .todo, 1024, isDeleted: true)])

        let board = try await store.fetchAll()
        #expect(board.isEmpty)
    }
}
