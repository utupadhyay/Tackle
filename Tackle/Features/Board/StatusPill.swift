//
//  StatusPill.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

/// A section header: stage dot, the stage name, and the count of tasks sitting in it.
struct StatusPill: View {
    let status: TaskStatus
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.stage(status))
                .frame(width: 8, height: 8)

            // At accessibility sizes "IN PROGRESS" is wider than the row; shrinking it beats
            // breaking the word across lines.
            Text(status.title.uppercased())
                .fontDesign(.rounded)
                .foregroundStyle(Theme.stage(status))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(count, format: .number)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}
