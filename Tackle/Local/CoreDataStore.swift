//
//  CoreDataStore.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import CoreData
import Synchronization

/// The source of truth. `NSManagedObject` never leaves this type — everything above it
/// works in `TaskItem` structs.
nonisolated final class CoreDataStore: LocalStoreProtocol {
    private let stack: CoreDataStack
    private let subscribers = Mutex<[UUID: AsyncStream<[TaskItem]>.Continuation]>([:])

    private var writer: NSManagedObjectContext { stack.writer }

    init(stack: CoreDataStack) {
        self.stack = stack
    }

    // MARK: - Reading

    var tasks: AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            let key = UUID()
            subscribers.withLock { $0[key] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.subscribers.withLock { $0[key] = nil }
            }
            Task { [weak self] in
                guard let self else { return }
                continuation.yield((try? await self.fetchAll()) ?? [])
            }
        }
    }

    func fetchAll() async throws -> [TaskItem] {
        try await writer.perform { [writer] in
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "deletedFlag == NO")
            let pending = try Self.pendingTaskIds(in: writer)
            return try writer.fetch(request)
                .compactMap { Self.item(from: $0, pendingIds: pending) }
                .sorted(by: TaskItem.boardOrder)
        }
    }

    func task(id: UUID) async throws -> TaskItem? {
        try await writer.perform { [writer] in
            guard let row = try Self.taskRow(id: id, in: writer) else { return nil }
            return Self.item(from: row, pendingIds: try Self.pendingTaskIds(in: writer))
        }
    }

    // MARK: - Writing

    func save(_ task: TaskItem) async throws {
        try await writer.perform { [writer] in
            let row = try Self.taskRow(id: task.id, in: writer) ?? CDTask(context: writer)
            Self.apply(task, to: row)
            try Self.upsertPendingPush(taskId: task.id, in: writer)
            try writer.save()
        }
        await broadcast()
    }

    func mergeRemote(_ tasks: [TaskItem]) async throws {
        try await writer.perform { [writer] in
            for task in tasks {
                let existing = try Self.taskRow(id: task.id, in: writer)
                if task.isDeleted {
                    if let existing { writer.delete(existing) }
                    continue
                }
                if let existing {
                    guard let localUpdatedAt = existing.updatedAt,
                          task.updatedAt > localUpdatedAt else { continue }
                    Self.apply(task, to: existing)
                } else {
                    Self.apply(task, to: CDTask(context: writer))
                }
            }
            guard writer.hasChanges else { return }
            try writer.save()
        }
        await broadcast()
    }

    // MARK: - Outbox

    func pendingPushes() async throws -> [PendingPush] {
        try await writer.perform { [writer] in
            let request = CDPendingPush.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "queuedAt", ascending: true)]
            return try writer.fetch(request).compactMap(Self.push(from:))
        }
    }

    func pendingTaskIds() async throws -> Set<UUID> {
        try await writer.perform { [writer] in
            try Self.pendingTaskIds(in: writer)
        }
    }

    func markPushing(_ push: PendingPush, updatedAt: Date) async throws {
        try await writer.perform { [writer] in
            guard let row = try Self.pushRow(id: push.id, in: writer) else { return }
            row.pushedUpdatedAt = updatedAt
            try writer.save()
        }
    }

    func clearPush(_ id: UUID) async throws {
        try await writer.perform { [writer] in
            guard let row = try Self.pushRow(id: id, in: writer) else { return }
            writer.delete(row)
            try writer.save()
        }
        await broadcast()
    }

    // MARK: - Publishing

    private func broadcast() async {
        let snapshot = (try? await fetchAll()) ?? []
        subscribers.withLock { subscribers in
            for continuation in subscribers.values { continuation.yield(snapshot) }
        }
    }

    // MARK: - Fetch helpers

    private static func taskRow(id: UUID, in context: NSManagedObjectContext) throws -> CDTask? {
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func pushRow(id: UUID, in context: NSManagedObjectContext) throws -> CDPendingPush? {
        let request = CDPendingPush.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// One row per task, however many times it was edited offline.
    private static func upsertPendingPush(taskId: UUID, in context: NSManagedObjectContext) throws {
        let request = CDPendingPush.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId as CVarArg)
        request.fetchLimit = 1
        guard try context.fetch(request).isEmpty else { return }

        let row = CDPendingPush(context: context)
        row.id = UUID()
        row.taskId = taskId
        row.queuedAt = .now
        row.pushedUpdatedAt = nil
    }

    private static func pendingTaskIds(in context: NSManagedObjectContext) throws -> Set<UUID> {
        let request = CDPendingPush.fetchRequest()
        return Set(try context.fetch(request).compactMap(\.taskId))
    }

    // MARK: - Mapping

    private static func item(from row: CDTask, pendingIds: Set<UUID>) -> TaskItem? {
        guard let id = row.id,
              let title = row.title,
              let statusRaw = row.statusRaw,
              let status = TaskStatus(rawValue: statusRaw),
              let createdAt = row.createdAt,
              let updatedAt = row.updatedAt
        else { return nil }

        return TaskItem(
            id: id,
            title: title,
            details: row.details ?? "",
            status: status,
            sortIndex: row.sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: row.deletedFlag,
            isSynced: !pendingIds.contains(id)
        )
    }

    private static func apply(_ task: TaskItem, to row: CDTask) {
        row.id = task.id
        row.title = task.title
        row.details = task.details
        row.statusRaw = task.status.rawValue
        row.sortIndex = task.sortIndex
        row.createdAt = task.createdAt
        row.updatedAt = task.updatedAt
        row.deletedFlag = task.isDeleted
    }

    private static func push(from row: CDPendingPush) -> PendingPush? {
        guard let id = row.id, let taskId = row.taskId, let queuedAt = row.queuedAt else { return nil }
        return PendingPush(id: id, taskId: taskId, queuedAt: queuedAt, pushedUpdatedAt: row.pushedUpdatedAt)
    }

}
