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

        do {
            try await FirebaseBootstrap.start()
        } catch {
            return
        }

        let service = SyncService(
            local: store,
            remote: FirestoreStore(),
            monitor: NetworkMonitor(),
            status: syncStatus
        )
        sync = service
        (repository as? TaskRepository)?.attach(sync: service)
        await service.start()
    }
}
