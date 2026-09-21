//
//  TackleApp.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

@main
struct TackleApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: container.makeBoardViewModel(), router: container.router)
                .task { await container.bootstrapFirebase() }
        }
    }
}
