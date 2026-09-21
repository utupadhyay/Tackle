//
//  AppContainer.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// The only place concrete types are named.
@Observable
final class AppContainer {
    let router = Router()
    let syncStatus = SyncStatus()

    // `lazy` can't be observed, and none of these are UI state.
    @ObservationIgnored private let stack = CoreDataStack()
    @ObservationIgnored private lazy var store: LocalStoreProtocol = CoreDataStore(stack: stack)
    @ObservationIgnored private lazy var repository: TaskRepositoryProtocol = TaskRepository(local: store)
    @ObservationIgnored private var sync: SyncService?

    func makeBoardViewModel() -> BoardViewModel {
        BoardViewModel(repository: repository, router: router, status: syncStatus)
    }

    func makeEditorViewModel(_ task: TaskItem?) -> TaskEditorViewModel {
        .init(task: task, repository: repository, router: router)
    }

    /// If this fails the app keeps working exactly as it did without Firebase — that is the
    /// whole point. It never blocks the UI and never surfaces an error.
    func bootstrapFirebase() async {
        guard sync == nil else { return }

        FirebaseBootstrap.configure()

        let monitor = NetworkMonitor()

        // The anonymous credential is the one part of startup that needs the network. On a
        // first launch in airplane mode, giving up here would leave sync detached for the
        // whole session and the outbox would sit there even after the network came back, so
        // retry on each reconnect until it takes.
        var connectivity = monitor.changes.makeAsyncIterator()
        while (try? await FirebaseBootstrap.signIn()) == nil {
            var reconnected = false
            while !reconnected, let isOnline = await connectivity.next() {
                reconnected = isOnline
            }
            guard reconnected else { return }
        }

        let service = SyncService(
            local: store,
            remote: FirestoreStore(),
            monitor: monitor,
            status: syncStatus
        )
        sync = service
        (repository as? TaskRepository)?.attach(sync: service)
        await service.start()
    }
}
