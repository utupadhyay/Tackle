//
//  TaskRepositoryTests.swift
//  TackleTests
//
//  The rules the UI relies on but never states: where a new task goes, what delete means,
//  and what a drag resolves to. Run against a real store.
//

import Foundation
import Testing
@testable import Tackle

@Suite("Task repository", .serialized)
struct TaskRepositoryTests {

    private func repository() -> (TaskRepository, CoreDataStore) {
        let store = makeStore()
        return (TaskRepository(local: store), store)
    }

    // MARK: - Creating

    @Test("The first task in a section starts at the default gap")
    func firstTaskTakesTheGap() async throws {
        let (repository, store) = repository()

        try await repository.create(title: "a", details: "", status: .todo)

        let tasks = try await store.fetchAll()
        #expect(tasks.count == 1)
        #expect(tasks[0].sortIndex == SortIndex.gap)
    }

    /// The one place that doesn't go to the top: typing several tasks in a row is building a
    /// queue, so each belongs after the last.
    @Test("New tasks append to the bottom of their section")
    func createAppends() async throws {
        let (repository, store) = repository()

        try await repository.create(title: "first", details: "", status: .todo)
        try await repository.create(title: "second", details: "", status: .todo)
        try await repository.create(title: "third", details: "", status: .todo)

        let tasks = try await store.fetchAll()
        #expect(tasks.map(\.title) == ["first", "second", "third"])
    }

    @Test("A new task only looks at its own section")
    func createIgnoresOtherSections() async throws {
        let (repository, store) = repository()
        try await repository.create(title: "todo", details: "", status: .todo)

        try await repository.create(title: "done", details: "", status: .done)

        let done = try await store.fetchAll().first { $0.status == .done }
        #expect(done?.sortIndex == SortIndex.gap)
    }

    @Test("Creating queues the task for push")
    func createQueuesAPush() async throws {
        let (repository, store) = repository()

        try await repository.create(title: "a", details: "", status: .todo)

        let pending = try await store.pendingPushes()
        #expect(pending.count == 1)
    }

    // MARK: - Deleting

    /// A hard delete would leave the server no way to learn about it, and would let a pull
    /// resurrect the task.
    @Test("Delete is a soft delete that hides the task and queues the tombstone")
    func deleteIsSoft() async throws {
        let (repository, store) = repository()
        try await repository.create(title: "a", details: "", status: .todo)
        let created = try await store.fetchAll()[0]

        try await repository.delete(created.id)

        let board = try await store.fetchAll()
        #expect(board.isEmpty)

        let stored = try await store.task(id: created.id)
        #expect(stored?.isDeleted == true)

        let pending = try await store.pendingTaskIds()
        #expect(pending == [created.id])
    }

    @Test("Deleting something that isn't there does nothing")
    func deleteUnknownIsANoOp() async throws {
        let (repository, store) = repository()

        try await repository.delete(UUID())

        let pending = try await store.pendingPushes()
        #expect(pending.isEmpty)
    }

    // MARK: - Moving

    @Test("Moving between two rows takes the midpoint")
    func moveTakesTheMidpoint() async throws {
        let (repository, store) = repository()
        try await repository.create(title: "first", details: "", status: .todo)
        try await repository.create(title: "second", details: "", status: .todo)
        try await repository.create(title: "third", details: "", status: .todo)
        let tasks = try await store.fetchAll()

        try await repository.move(tasks[2].id, to: .todo, above: tasks[0].id, below: tasks[1].id)

        let reordered = try await store.fetchAll()
        #expect(reordered.map(\.title) == ["first", "third", "second"])
    }

    @Test("Moving to the top lands above everything")
    func moveToTop() async throws {
        let (repository, store) = repository()
        try await repository.create(title: "first", details: "", status: .todo)
        try await repository.create(title: "second", details: "", status: .todo)
        let tasks = try await store.fetchAll()

        try await repository.move(tasks[1].id, to: .todo, above: nil, below: tasks[0].id)

        let reordered = try await store.fetchAll()
        #expect(reordered.map(\.title) == ["second", "first"])
    }

    /// A drag across sections is one write, not a status change followed by a reorder.
    @Test("A move can change section and position together")
    func moveChangesSectionAndPosition() async throws {
        let (repository, store) = repository()
        try await repository.create(title: "todo", details: "", status: .todo)
        try await repository.create(title: "doing first", details: "", status: .inProgress)
        try await repository.create(title: "doing second", details: "", status: .inProgress)
        let tasks = try await store.fetchAll()
        let moving = try #require(tasks.first { $0.title == "todo" })
        let first = try #require(tasks.first { $0.title == "doing first" })
        let second = try #require(tasks.first { $0.title == "doing second" })

        try await repository.move(moving.id, to: .inProgress, above: first.id, below: second.id)

        let board = try await store.fetchAll()
        #expect(board.map(\.title) == ["doing first", "todo", "doing second"])
        #expect(board.allSatisfy { $0.status == .inProgress })
    }

    @Test("Moving something that isn't there does nothing")
    func moveUnknownIsANoOp() async throws {
        let (repository, store) = repository()

        try await repository.move(UUID(), to: .done, above: nil, below: nil)

        let board = try await store.fetchAll()
        #expect(board.isEmpty)
    }
}
