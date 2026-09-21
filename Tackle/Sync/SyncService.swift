//
//  SyncService.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// Two independent halves: a push loop you trigger, and an inbound stream that pushes to you.
actor SyncService {
    private let local: LocalStoreProtocol
    private let remote: RemoteStoreProtocol
    private let monitor: NetworkMonitoring

    private var isPushing = false
    private var needsAnotherPass = false
    private var listenerTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    init(local: LocalStoreProtocol, remote: RemoteStoreProtocol, monitor: NetworkMonitoring) {
        self.local = local
        self.remote = remote
        self.monitor = monitor
    }

    func start() {
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await remoteTasks in self.remote.remoteChanges() {
                await self.merge(remoteTasks)
            }
        }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await online in self.monitor.changes where online {
                await self.pushPending()
            }
        }
        Task { await pushPending() }
    }

    func stop() {
        listenerTask?.cancel()
        monitorTask?.cancel()
        listenerTask = nil
        monitorTask = nil
    }

    /// Actors are reentrant: at `await remote.push` this actor yields and a second call can
    /// start. Connectivity returning, the app foregrounding and a manual refresh can all fire
    /// within the same second, so the flag is required — isolation alone is not enough.
    func pushPending() async {
        if isPushing {
            needsAnotherPass = true
            return
        }
        isPushing = true
        defer { isPushing = false }

        repeat {
            needsAnotherPass = false
            guard let pushes = try? await local.pendingPushes() else { break }

            for push in pushes {
                guard let task = try? await local.task(id: push.taskId) else {
                    try? await local.clearPush(push.id)
                    continue
                }

                let sentUpdatedAt = task.updatedAt
                try? await local.markPushing(push, updatedAt: sentUpdatedAt)

                do {
                    try await remote.push(task)
                    // Clear only if the task hasn't been edited since this push started.
                    let current = try? await local.task(id: push.taskId)
                    if current?.updatedAt == sentUpdatedAt {
                        try? await local.clearPush(push.id)
                    }
                } catch {
                    break // offline or transient — leave the row, stop the pass
                }
            }
        } while needsAnotherPass
    }

    /// Skipping tasks with a pending push is what makes the listener's arbitrary timing safe,
    /// and it is also why our own echoed write is harmless: once the outbox row clears, the
    /// echo carries exactly the `updatedAt` we wrote, so it fails the `>` test in `mergeRemote`.
    private func merge(_ remoteTasks: [TaskItem]) async {
        guard let pendingIds = try? await local.pendingTaskIds() else { return }
        let mergeable = remoteTasks.filter { !pendingIds.contains($0.id) }
        guard !mergeable.isEmpty else { return }
        try? await local.mergeRemote(mergeable)
    }
}
