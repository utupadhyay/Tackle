//
//  BoardViewModel.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

@Observable
final class BoardViewModel {
    private(set) var tasks: [TaskItem] = []
    var pendingDeletion: TaskItem?
    var taskBeingMoved: TaskItem?
    var saveFailed = false

    private let repository: TaskRepositoryProtocol
    private let router: Router
    private let status: SyncStatus

    init(repository: TaskRepositoryProtocol, router: Router, status: SyncStatus) {
        self.repository = repository
        self.router = router
        self.status = status
    }

    var isEmpty: Bool { tasks.isEmpty }

    // MARK: - Status capsule

    private var waitingCount: Int {
        tasks.count { !$0.isSynced }
    }

    /// Nil means no capsule at all. Silence is the synced state.
    ///
    /// Queued work only reads as "Syncing…" while a push is actually in flight — anything else
    /// queued and not moving is reported as offline, which stays true whether the network is
    /// down or the server is simply unreachable.
    var capsuleText: String? {
        let waiting = waitingCount
        if waiting > 0 {
            return status.isPushing ? "Syncing…" : "Offline · \(waiting) waiting"
        }
        // The one thing the app genuinely doesn't know yet: whether the server has anything.
        guard status.isOnline, !status.hasLoadedRemote else { return nil }
        return "Checking for tasks…"
    }

    var capsuleGlyph: String {
        status.isPushing ? "arrow.trianglehead.2.clockwise" : "clock"
    }

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }
    }

    /// Core Data answers immediately, so there is no loading state to model here.
    func observe() async {
        for await tasks in repository.tasks {
            self.tasks = tasks
        }
    }

    // MARK: - Navigation

    func newTask() { router.present(.editor(nil)) }
    func edit(_ task: TaskItem) { router.present(.editor(task)) }

    func editorViewModel(for task: TaskItem?) -> TaskEditorViewModel {
        TaskEditorViewModel(task: task, repository: repository, router: router)
    }

    // MARK: - Mutations

    func confirmDeletion() {
        guard let task = pendingDeletion else { return }
        pendingDeletion = nil
        perform { try await self.repository.delete(task.id) }
    }

    func destinations(for task: TaskItem) -> [TaskStatus] {
        TaskStatus.allCases.filter { $0 != task.status }
    }

    /// Moving between sections lands the task at the bottom of the target section.
    func move(_ task: TaskItem, to status: TaskStatus) {
        let above = tasks(in: status).last?.id
        perform { try await self.repository.move(task.id, to: status, above: above, below: nil) }
    }

    /// SwiftUI computes `destination` before the row is removed, so it is off by one
    /// when a task moves downward.
    func move(in section: [TaskItem], from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first else { return }

        var reordered = section
        let moved = reordered.remove(at: fromIndex)
        let insertAt = destination > fromIndex ? destination - 1 : destination
        reordered.insert(moved, at: insertAt)

        let above = insertAt > 0 ? reordered[insertAt - 1].id : nil
        let below = insertAt < reordered.count - 1 ? reordered[insertAt + 1].id : nil

        perform { try await self.repository.move(moved.id, to: moved.status, above: above, below: below) }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { saveFailed = true }
        }
    }
}
