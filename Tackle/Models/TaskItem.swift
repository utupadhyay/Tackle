//
//  TaskItem.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// Named `TaskItem`, not `Task` — `Task` collides with Swift Concurrency.
nonisolated struct TaskItem: Identifiable, Hashable, Sendable {
    /// Client-generated; doubles as the Firestore document ID.
    let id: UUID
    var title: String
    var details: String
    var status: TaskStatus
    var sortIndex: Double
    let createdAt: Date
    var updatedAt: Date
    /// Soft delete. The board query filters these out.
    var isDeleted: Bool
    /// Derived at read time — true when no outbox row references this id. Never stored.
    var isSynced: Bool

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        status: TaskStatus,
        sortIndex: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        isSynced: Bool = true
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.isSynced = isSynced
    }
}
