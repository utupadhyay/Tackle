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

    var tasks: AsyncStream<[TaskItem]> { AsyncStream { $0.finish() } }

    func create(title: String, details: String, status: TaskStatus) async throws {}
    func update(_ task: TaskItem) async throws {}
    func delete(_ id: UUID) async throws {}
    func sync() async {}

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
