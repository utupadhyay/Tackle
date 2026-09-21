//
//  PendingPush.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// The outbox row. Just an id — a Firestore write is an upsert of the task's current state,
/// so create, update and delete need no operation kind or stored payload.
nonisolated struct PendingPush: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskId: UUID
    let queuedAt: Date
    /// Set while a push is in flight.
    var pushedUpdatedAt: Date?
}
