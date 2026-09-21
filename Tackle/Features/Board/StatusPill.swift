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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(Theme.labelSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(background, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    /// The capsule floats over the list, so the material is doing real work here — without it
    /// the rows behind show through an opaque shape and the capsule looks stuck on. Reduce
    /// Transparency asks for exactly that trade anyway: a flat card colour, legible over
    /// anything, at the cost of looking pasted on.
    private var background: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Theme.card) : AnyShapeStyle(.regularMaterial)
    }
}
