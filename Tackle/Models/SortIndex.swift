//
//  SortIndex.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// Fractional indexing, so a reorder writes one row instead of renumbering a section.
nonisolated enum SortIndex {
    static let gap: Double = 1024

    /// `above` is the visually higher neighbour and therefore the smaller index.
    static func between(above: Double?, below: Double?) -> Double {
        switch (above, below) {
        case (nil, nil):
            gap
        case (nil, let below?):
            below - gap
        case (let above?, nil):
            above + gap
        case (let above?, let below?):
            (above + below) / 2
        }
    }
}
