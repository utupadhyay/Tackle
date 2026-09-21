//
//  Theme.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

/// The palette from SCREENS.md §4. Dark values are re-picked for a dark ground, not inverted,
/// and every text colour clears 4.5:1.
enum Theme {
    static let canvas = Color(light: 0xF4F3F8, dark: 0x0E0E13)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1A22)
    static let label = Color(light: 0x1A1A24, dark: 0xF2F1F7)
    static let labelSecondary = Color(light: 0x6E6C7E, dark: 0x9C9AAC)
    static let tint = Color(light: 0x4E5BC6, dark: 0xA3ABF2)

    static let todo = Color(light: 0x5A64B0, dark: 0xA8B0EA)
    static let inProgress = Color(light: 0x9A5E12, dark: 0xE8B569)
    static let done = Color(light: 0x3F7A5E, dark: 0x86C7A4)

    /// The danger colour appears in exactly one place in the app: Delete.
    static let destructive = Color(light: 0xC4453D, dark: 0xFF8A80)

    static func stage(_ status: TaskStatus) -> Color {
        switch status {
        case .todo: todo
        case .inProgress: inProgress
        case .done: done
        }
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
