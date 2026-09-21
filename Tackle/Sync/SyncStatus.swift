//
//  SyncStatus.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// What the status capsule needs to know. Presentation state only — task data still reaches
/// the UI through `TaskRepository` and nothing else.
@MainActor
@Observable
final class SyncStatus {
    var isOnline = true
    var isPushing = false
    /// Starts true: with no remote attached there is nothing to wait to hear from.
    var hasLoadedRemote = true
}
