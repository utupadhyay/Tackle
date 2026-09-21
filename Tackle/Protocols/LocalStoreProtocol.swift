//
//  LocalStoreProtocol.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

nonisolated protocol LocalStoreProtocol: Sendable {
    var tasks: AsyncStream<[TaskItem]> { get }
    func fetchAll() async throws -> [TaskItem]
    func task(id: UUID) async throws -> TaskItem?

    /// Saves the task and queues a push, in ONE transaction.
    func save(_ task: TaskItem) async throws

    func pendingPushes() async throws -> [PendingPush]
    func pendingTaskIds() async throws -> Set<UUID>
    func markPushing(_ push: PendingPush, updatedAt: Date) async throws
    func clearPush(_ id: UUID) async throws

    /// Applies remote tasks in ONE transaction.
    func mergeRemote(_ tasks: [TaskItem]) async throws
}
