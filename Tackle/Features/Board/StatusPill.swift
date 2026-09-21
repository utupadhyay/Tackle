//
//  StatusPill.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

/// The status capsule, bottom-left. It obeys the same rule as the rails: it only appears when
/// there is something to say. All synced, and it is not there at all.
struct StatusPill: View {
    let text: String
    let glyph: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(Theme.labelSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
