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
    private let stack = CoreDataStack()
    // `lazy` can't be observed, and none of these are UI state.
    @ObservationIgnored private lazy var store: LocalStoreProtocol = CoreDataStore(stack: stack)
    @ObservationIgnored private lazy var repository: TaskRepositoryProtocol = TaskRepository(local: store)

    func makeBoardViewModel() -> BoardViewModel {
        BoardViewModel(repository: repository, router: router)
    }

    func makeEditorViewModel(_ task: TaskItem?) -> TaskEditorViewModel {
        .init(task: task, repository: repository, router: router)
    }
}
