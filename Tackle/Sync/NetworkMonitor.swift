//
//  NetworkMonitor.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation
import Network
import Synchronization

/// The protocol is what lets the sync tests simulate connectivity returning.
nonisolated protocol NetworkMonitoring: Sendable {
    var isOnline: Bool { get async }
    /// Emits on transitions.
    var changes: AsyncStream<Bool> { get }
}

nonisolated final class NetworkMonitor: NetworkMonitoring {
    private struct State {
        var isOnline = true
        var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let path = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.utkarsh.Tackle.network")
    private let state = Mutex(State())

    init() {
        path.pathUpdateHandler = { [weak self] path in
            self?.update(isOnline: path.status == .satisfied)
        }
        path.start(queue: queue)
    }

    deinit {
        path.cancel()
    }

    var isOnline: Bool {
        state.withLock { $0.isOnline }
    }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let key = UUID()
            state.withLock { $0.subscribers[key] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.subscribers[key] = nil }
            }
        }
    }

    private func update(isOnline: Bool) {
        let subscribers: [AsyncStream<Bool>.Continuation] = state.withLock { state in
            guard state.isOnline != isOnline else { return [] }
            state.isOnline = isOnline
            return Array(state.subscribers.values)
        }
        for continuation in subscribers { continuation.yield(isOnline) }
    }
}
