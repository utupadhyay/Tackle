//
//  Router.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

@Observable
final class Router {
    /// Pushed destinations.
    var path = NavigationPath()
    /// Modal presentation.
    var sheet: Route?

    func present(_ route: Route) { sheet = route }
    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func dismiss() { sheet = nil }
}
