//
//  RemoteStoreProtocol.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// Nothing above this protocol knows Firebase exists. Part 2 adds the only conformance.
nonisolated protocol RemoteStoreProtocol: Sendable {
    func push(_ task: TaskItem) async throws

    /// Live stream from the remote. First value is the full snapshot,
    /// then one value per remote change. Replaces polling entirely.
    func remoteChanges() -> AsyncStream<[TaskItem]>
}
