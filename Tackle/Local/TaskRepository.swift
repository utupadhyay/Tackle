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

    /// New tasks append to the bottom of their section.
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

    func update(_ task: TaskItem) async throws {
        var updated = task
        updated.updatedAt = .now
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

    private func pushInBackground() {
        guard let service = sync.withLock({ $0 }) else { return }
        Task { await service.pushPending() }
    }
}
