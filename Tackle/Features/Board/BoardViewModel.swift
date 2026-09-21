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

    init(repository: TaskRepositoryProtocol, router: Router) {
        self.repository = repository
        self.router = router
    }

    var isEmpty: Bool { tasks.isEmpty }

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
