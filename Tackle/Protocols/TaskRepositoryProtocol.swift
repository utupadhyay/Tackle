//
//  TaskRepositoryProtocol.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// The only data API the UI sees.
nonisolated protocol TaskRepositoryProtocol: Sendable {
    /// Live, ordered, excludes deleted.
    var tasks: AsyncStream<[TaskItem]> { get }

    func create(title: String, details: String, status: TaskStatus) async throws
    func update(_ task: TaskItem) async throws
    func delete(_ id: UUID) async throws
    func move(_ id: UUID, to status: TaskStatus, above: UUID?, below: UUID?) async throws
    /// Never throws to the UI.
    func sync() async
}
