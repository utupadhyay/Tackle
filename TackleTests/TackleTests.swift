//
//  TackleTests.swift
//  TackleTests
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation
import Testing
@testable import Tackle

@Suite("SortIndex")
struct SortIndexTests {

    @Test("An empty section starts at the gap")
    func emptySection() {
        #expect(SortIndex.between(above: nil, below: nil) == 1024)
    }

    @Test("Moving to the top sits a gap above the first row")
    func top() {
        #expect(SortIndex.between(above: nil, below: 1024) == 0)
        #expect(SortIndex.between(above: nil, below: 512) == -512)
    }

    @Test("Moving to the bottom sits a gap below the last row")
    func bottom() {
        #expect(SortIndex.between(above: 1024, below: nil) == 2048)
    }

    @Test("Moving between two rows takes the midpoint")
    func middle() {
        #expect(SortIndex.between(above: 1024, below: 2048) == 1536)
        #expect(SortIndex.between(above: 0, below: 1) == 0.5)
    }

    @Test("Repeated splits between the same pair stay ordered")
    func repeatedSplits() {
        var above = 1024.0
        let below = 2048.0

        for _ in 0..<10 {
            let index = SortIndex.between(above: above, below: below)
            #expect(index > above && index < below)
            above = index
        }
    }
}

/// Records the neighbours a move resolves to, which is the part with the off-by-one.
private final class RecordingRepository: TaskRepositoryProtocol, @unchecked Sendable {
    private(set) var moved: (id: UUID, status: TaskStatus, above: UUID?, below: UUID?)?

    /// What the board sees when it starts observing.
    var seed: [TaskItem] = []

    var tasks: AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            continuation.yield(seed)
            continuation.finish()
        }
    }

    private(set) var statusChanged: (id: UUID, status: TaskStatus)?

    func create(title: String, details: String, status: TaskStatus) async throws {}
    func update(_ task: TaskItem) async throws {}
    func delete(_ id: UUID) async throws {}
    func sync() async {}

    func changeStatus(_ id: UUID, to status: TaskStatus) async throws {
        statusChanged = (id, status)
    }

    func move(_ id: UUID, to status: TaskStatus, above: UUID?, below: UUID?) async throws {
        moved = (id, status, above, below)
    }
}

@Suite("Reordering")
@MainActor
struct ReorderTests {

    private func section(_ count: Int) -> [TaskItem] {
        (0..<count).map { index in
            TaskItem(
                id: UUID(),
                title: "Task \(index)",
                details: "",
                status: .todo,
                sortIndex: Double(index + 1) * SortIndex.gap,
                createdAt: .now,
                updatedAt: .now,
                isDeleted: false,
                isSynced: true
            )
        }
    }

    private func move(
        _ tasks: [TaskItem],
        from: Int,
        to: Int
    ) async -> (id: UUID, status: TaskStatus, above: UUID?, below: UUID?)? {
        let repository = RecordingRepository()
        let viewModel = BoardViewModel(
            repository: repository,
            router: Router(),
            status: SyncStatus()
        )
        viewModel.move(in: tasks, from: IndexSet(integer: from), to: to)

        // `move` hands off to a detached Task.
        for _ in 0..<100 where repository.moved == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return repository.moved
    }

    @Test("Dragging the last row to the top leaves nothing above it")
    func toTop() async {
        let tasks = section(3)
        let result = await move(tasks, from: 2, to: 0)

        #expect(result?.id == tasks[2].id)
        #expect(result?.above == nil)
        #expect(result?.below == tasks[0].id)
    }

    @Test("Dragging the first row to the bottom leaves nothing below it")
    func toBottom() async {
        let tasks = section(3)
        // SwiftUI passes one past the end when a row moves to the bottom.
        let result = await move(tasks, from: 0, to: 3)

        #expect(result?.above == tasks[2].id)
        #expect(result?.below == nil)
    }

    @Test("A downward drag accounts for the row leaving its old slot")
    func downwardOffByOne() async {
        let tasks = section(4)
        // SwiftUI numbers the drop against the list that still contains the row, so 3 means
        // "before the old row 3" — landing between rows 2 and 3, not after row 3.
        let result = await move(tasks, from: 0, to: 3)

        #expect(result?.above == tasks[2].id)
        #expect(result?.below == tasks[3].id)
    }

    @Test("An upward drag needs no adjustment")
    func upward() async {
        let tasks = section(4)
        let result = await move(tasks, from: 3, to: 1)

        #expect(result?.above == tasks[0].id)
        #expect(result?.below == tasks[1].id)
    }

    @Test("Reordering keeps the row in its own section")
    func keepsStatus() async {
        let tasks = section(3)
        let result = await move(tasks, from: 2, to: 0)

        #expect(result?.status == .todo)
    }
}

/// The board is one flat list of headings and tasks, so a drop arrives as an index into that
/// whole list. These cover the translation back into "which stage, and where in it".
@Suite("Dragging across stages")
@MainActor
struct FlatDragTests {

    /// Three To Do tasks and one In Progress task, which lays out as:
    /// `0` To Do heading, `1...3` its tasks, `4` In Progress heading, `5` its task,
    /// `6` Done heading.
    private func board() -> (BoardViewModel, RecordingRepository, [TaskItem]) {
        let tasks = [
            TaskItem(title: "a", status: .todo, sortIndex: 1024),
            TaskItem(title: "b", status: .todo, sortIndex: 2048),
            TaskItem(title: "c", status: .todo, sortIndex: 3072),
            TaskItem(title: "d", status: .inProgress, sortIndex: 1024),
        ]
        let repository = RecordingRepository()
        repository.seed = tasks
        let viewModel = BoardViewModel(
            repository: repository,
            router: Router(),
            status: SyncStatus()
        )
        return (viewModel, repository, tasks)
    }

    private func drag(from: Int, to: Int) async -> RecordingRepository {
        let (viewModel, repository, _) = board()
        await viewModel.observe()
        viewModel.move(from: IndexSet(integer: from), to: to)

        // Both paths hand off to a detached Task.
        for _ in 0..<100 where repository.moved == nil && repository.statusChanged == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return repository
    }

    @Test("Dropping into another stage changes status and keeps the drop position")
    func intoAnotherStage() async {
        let (viewModel, repository, tasks) = board()
        await viewModel.observe()
        // Above the one task already in In Progress.
        viewModel.move(from: IndexSet(integer: 1), to: 5)

        for _ in 0..<100 where repository.moved == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(repository.moved?.status == .inProgress)
        #expect(repository.moved?.above == nil)
        #expect(repository.moved?.below == tasks[3].id)
        // Position came from the drop, so the top-landing rule stays out of it.
        #expect(repository.statusChanged == nil)
    }

    /// The case a drag most easily gets wrong: arriving below a row rather than above it.
    @Test("Dropping below a row in another stage lands under it")
    func belowARowInAnotherStage() async {
        let (viewModel, repository, tasks) = board()
        await viewModel.observe()
        viewModel.move(from: IndexSet(integer: 1), to: 6)

        for _ in 0..<100 where repository.moved == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(repository.moved?.status == .inProgress)
        #expect(repository.moved?.above == tasks[3].id)
        #expect(repository.moved?.below == nil)
    }

    @Test("Dropping past the last row lands in the final stage")
    func intoTrailingEmptyStage() async {
        let repository = await drag(from: 1, to: 7)

        #expect(repository.moved?.status == .done)
        #expect(repository.moved?.above == nil)
        #expect(repository.moved?.below == nil)
    }

    @Test("Dropping within the same stage reorders instead of changing status")
    func withinOwnStage() async {
        let (viewModel, repository, tasks) = board()
        await viewModel.observe()
        viewModel.move(from: IndexSet(integer: 1), to: 3)

        for _ in 0..<100 where repository.moved == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(repository.statusChanged == nil)
        #expect(repository.moved?.id == tasks[0].id)
        #expect(repository.moved?.above == tasks[1].id)
        #expect(repository.moved?.below == tasks[2].id)
    }

    @Test("Dropping above the first heading stays in the first stage")
    func aboveEverything() async {
        let (viewModel, repository, tasks) = board()
        await viewModel.observe()
        viewModel.move(from: IndexSet(integer: 3), to: 0)

        for _ in 0..<100 where repository.moved == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(repository.moved?.above == nil)
        #expect(repository.moved?.below == tasks[0].id)
    }

    @Test("Dragging a heading does nothing")
    func headingIsInert() async {
        let (viewModel, repository, _) = board()
        await viewModel.observe()
        viewModel.move(from: IndexSet(integer: 4), to: 1)

        try? await Task.sleep(for: .milliseconds(50))

        #expect(repository.moved == nil)
        #expect(repository.statusChanged == nil)
    }
}

/// Just enough of the store to exercise the repository's positioning rules. Sync is never
/// attached, which is the same state the app is in before Firebase signs in.
private final class InMemoryStore: LocalStoreProtocol, @unchecked Sendable {
    private var storage: [UUID: TaskItem] = [:]

    init(_ tasks: [TaskItem] = []) {
        for task in tasks { storage[task.id] = task }
    }

    var tasks: AsyncStream<[TaskItem]> { AsyncStream { $0.finish() } }

    /// Mirrors Core Data, which filters soft-deleted rows out of every read.
    func fetchAll() async throws -> [TaskItem] {
        storage.values.filter { !$0.isDeleted }
    }

    func task(id: UUID) async throws -> TaskItem? { storage[id] }
    func save(_ task: TaskItem) async throws { storage[task.id] = task }

    func pendingPushes() async throws -> [PendingPush] { [] }
    func pendingTaskIds() async throws -> Set<UUID> { [] }
    func markPushing(_ push: PendingPush, updatedAt: Date) async throws {}
    func clearPush(_ id: UUID) async throws {}
    func mergeRemote(_ tasks: [TaskItem]) async throws {}
}

@Suite("Status changes")
struct StatusChangeTests {

    private func task(_ title: String, _ status: TaskStatus, _ sortIndex: Double) -> TaskItem {
        TaskItem(title: title, status: status, sortIndex: sortIndex)
    }

    @Test("A status change lands above everything already in the target section")
    func landsOnTop() async throws {
        let moving = task("moving", .todo, 5000)
        let store = InMemoryStore([
            moving,
            task("first", .inProgress, 1024),
            task("second", .inProgress, 2048)
        ])
        let repository = TaskRepository(local: store)

        try await repository.changeStatus(moving.id, to: .inProgress)

        let result = try #require(try await store.task(id: moving.id))
        #expect(result.status == .inProgress)
        #expect(result.sortIndex < 1024)
    }

    @Test("A status change into an empty section takes the default index")
    func emptySection() async throws {
        let moving = task("moving", .todo, 5000)
        let store = InMemoryStore([moving])
        let repository = TaskRepository(local: store)

        try await repository.changeStatus(moving.id, to: .done)

        let result = try #require(try await store.task(id: moving.id))
        #expect(result.sortIndex == SortIndex.gap)
    }

    @Test("Soft-deleted tasks don't hold the top slot")
    func ignoresDeleted() async throws {
        let moving = task("moving", .todo, 5000)
        var buried = task("deleted", .done, -9000)
        buried.isDeleted = true
        let store = InMemoryStore([moving, buried])
        let repository = TaskRepository(local: store)

        try await repository.changeStatus(moving.id, to: .done)

        let result = try #require(try await store.task(id: moving.id))
        #expect(result.sortIndex == SortIndex.gap)
    }

    @Test("Changing to the status it already has does nothing")
    func sameStatusIsANoOp() async throws {
        let unmoved = task("unmoved", .todo, 5000)
        let store = InMemoryStore([unmoved])
        let repository = TaskRepository(local: store)

        try await repository.changeStatus(unmoved.id, to: .todo)

        let result = try #require(try await store.task(id: unmoved.id))
        #expect(result.sortIndex == 5000)
        #expect(result.updatedAt == unmoved.updatedAt)
    }

    @Test("Repeated arrivals stack up rather than colliding")
    func repeatedArrivalsStayOrdered() async throws {
        let first = task("first", .todo, 100)
        let second = task("second", .todo, 200)
        let store = InMemoryStore([first, second, task("sitting", .done, 1024)])
        let repository = TaskRepository(local: store)

        try await repository.changeStatus(first.id, to: .done)
        try await repository.changeStatus(second.id, to: .done)

        let a = try #require(try await store.task(id: first.id))
        let b = try #require(try await store.task(id: second.id))
        #expect(b.sortIndex < a.sortIndex, "the later arrival sits above the earlier one")
    }

    @Test("The editor's status change lands on top too")
    func updateRepositionsOnStatusChange() async throws {
        var edited = task("edited", .todo, 5000)
        let store = InMemoryStore([edited, task("sitting", .done, 1024)])
        let repository = TaskRepository(local: store)

        edited.status = .done
        edited.title = "edited and moved"
        try await repository.update(edited)

        let result = try #require(try await store.task(id: edited.id))
        #expect(result.title == "edited and moved")
        #expect(result.sortIndex < 1024)
    }

    @Test("An edit that leaves the status alone keeps its position")
    func updateKeepsIndexWithoutStatusChange() async throws {
        var edited = task("edited", .todo, 5000)
        let store = InMemoryStore([edited])
        let repository = TaskRepository(local: store)

        edited.title = "retitled"
        try await repository.update(edited)

        let result = try #require(try await store.task(id: edited.id))
        #expect(result.sortIndex == 5000)
    }
}
