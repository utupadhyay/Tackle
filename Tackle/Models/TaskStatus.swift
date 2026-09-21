//
//  TaskStatus.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

nonisolated enum TaskStatus: String, CaseIterable, Sendable {
    case todo
    case inProgress
    case done

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}
