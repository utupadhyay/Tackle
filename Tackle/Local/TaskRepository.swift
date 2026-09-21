//
//  TaskRepository.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation
import Synchronization

nonisolated final class TaskRepository: TaskRepositoryProtocol {
    private let local: LocalStoreProtocol
    /// Attached once Firebase has signed in. Nil until then, and the app works either way.
    private let sync = Mutex<SyncService?>(nil)

    init(local: LocalStoreProtocol) {
        self.local = local
    }

    func attach(sync service: SyncService) {
        sync.withLock { $0 = service }
    }

    var tasks: AsyncStream<[TaskItem]> { local.tasks }

    /// New tasks append to the bottom — creating several in a row is building a queue, so each
    /// belongs after the last. This is the one case that doesn't go to the top.
    func create(title: String, details: String, status: TaskStatus) async throws {
        let bottom = try await local.fetchAll()
            .filter { $0.status == status }
            .map(\.sortIndex)
            .max()

        try await local.save(
            TaskItem(
                title: title,
                details: details,
                status: status,
                sortIndex: SortIndex.between(above: bottom, below: nil)
            )
        )
        pushInBackground()
    }

    /// A status change here — the editor's picker is the only way in — follows the same rule
    /// as everywhere else, so the editor doesn't need to know the rule or the target section.
    func update(_ task: TaskItem) async throws {
        var updated = task
        updated.updatedAt = .now

        let stored = try await local.task(id: task.id)
        if let stored, stored.status != task.status {
            updated.sortIndex = topIndex(of: task.status, in: try await local.fetchAll())
        }

        try await local.save(updated)
        pushInBackground()
    }

    /// Soft delete — the board query filters it out, and Part 2 pushes `deleted: true`.
    func delete(_ id: UUID) async throws {
        guard var task = try await local.task(id: id) else { return }
        task.isDeleted = true
        task.updatedAt = .now
        try await local.save(task)
        pushInBackground()
    }

    /// Changing status sends the task to the top of the section it lands in, so the user can
    /// see where it went instead of hunting for it in a long list. Position is only ever
    /// chosen by the user dragging a row, which goes through `move`.
    func changeStatus(_ id: UUID, to status: TaskStatus) async throws {
        guard var task = try await local.task(id: id), task.status != status else { return }

        task.status = status
        task.sortIndex = topIndex(of: status, in: try await local.fetchAll())
        task.updatedAt = .now
        try await local.save(task)
        pushInBackground()
    }

    /// Moving between sections and reordering within one are the same operation.
    func move(_ id: UUID, to status: TaskStatus, above: UUID?, below: UUID?) async throws {
        guard var task = try await local.task(id: id) else { return }
        let all = try await local.fetchAll()

        task.status = status
        task.sortIndex = SortIndex.between(
            above: above.flatMap { neighbour in all.first { $0.id == neighbour }?.sortIndex },
            below: below.flatMap { neighbour in all.first { $0.id == neighbour }?.sortIndex }
        )
        task.updatedAt = .now
        try await local.save(task)
        pushInBackground()
    }

    /// Never throws to the UI — a failed push just leaves its outbox row in place.
    func sync() async {
        await sync.withLock { $0 }?.pushPending()
    }

    /// One gap above whatever currently sits highest. Top insertion always subtracts, so it
    /// can't exhaust precision the way repeated midpoint splits can.
    private func topIndex(of status: TaskStatus, in all: [TaskItem]) -> Double {
        SortIndex.between(
            above: nil,
            below: all.filter { $0.status == status }.map(\.sortIndex).min()
        )
    }

    private func pushInBackground() {
        guard let service = sync.withLock({ $0 }) else { return }
        Task { await service.pushPending() }
    }
}
