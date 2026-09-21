//
//  TaskRow.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

struct TaskRow: View {
    let task: TaskItem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Theme.stage(task.status))
                .opacity(task.isSynced ? 1 : 0.35)
                .frame(width: 3)
                .animation(reduceMotion ? nil : .easeInOut, value: task.isSynced)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(task.status == .done ? Theme.labelSecondary : Theme.label)

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.subheadline)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }

            Spacer(minLength: 8)

            // Silence means synced; only the waiting state carries a glyph.
            if !task.isSynced {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.labelSecondary)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut, value: task.isSynced)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [task.title]
        if !task.details.isEmpty { parts.append(task.details) }
        parts.append(task.status.title)
        if !task.isSynced { parts.append("Waiting to sync") }
        return parts.joined(separator: ", ")
    }
}
