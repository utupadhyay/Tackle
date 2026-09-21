//
//  TaskEditorViewModel.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

@Observable
final class TaskEditorViewModel {
    var title: String
    var details: String
    var status: TaskStatus
    var saveFailed = false

    private let existing: TaskItem?
    private let repository: TaskRepositoryProtocol
    private let router: Router

    init(task: TaskItem?, repository: TaskRepositoryProtocol, router: Router) {
        self.existing = task
        self.repository = repository
        self.router = router
        self.title = task?.title ?? ""
        self.details = task?.details ?? ""
        self.status = task?.status ?? .todo
    }

    var isNew: Bool { existing == nil }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func cancel() { router.dismiss() }

    func save() {
        guard canSave else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = status

        Task {
            do {
                if var task = existing {
                    task.title = title
                    task.details = details
                    // If this changes the status, the repository repositions the task to the
                    // top of its new section, the same as a drag or the swipe action would.
                    task.status = status
                    try await repository.update(task)
                } else {
                    try await repository.create(title: title, details: details, status: status)
                }
                router.dismiss()
            } catch {
                saveFailed = true
            }
        }
    }
}
