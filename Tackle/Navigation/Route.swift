//
//  Route.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

enum Route: Hashable, Identifiable {
    /// `nil` = new task.
    case editor(TaskItem?)
    // future: .settings, .taskDetail(UUID), .debugPanel

    var id: String {
        switch self {
        case .editor(let task): "editor-\(task?.id.uuidString ?? "new")"
        }
    }
}
