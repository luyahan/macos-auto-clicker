//
//  TriggerPilotPalette.swift
//  auto-clicker
//
//  Colour tokens lifted verbatim from the Ardot "TriggerPilot" design file
//  (file 727793516651652 — nodes 7:1 "Macro Utility Window" and 2:410 "Macro Settings Panel").
//
//  Names describe the role each swatch plays in the design rather than its hue, as several
//  near-identical purples are deliberately reused for different purposes.
//

import SwiftUI

extension Color {
    /// Builds a colour from a `0xRRGGBB` literal so the values here stay diffable against the
    ///  hex swatches recorded in the design file.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum TPPalette {
    // MARK: - Chrome

    static let windowBackground = Color(hex: 0x05000F)
    static let panelBackground = Color(hex: 0x090316)

    static let trafficRed = Color(hex: 0xFF5F57)
    static let trafficYellow = Color(hex: 0xFFBD2D)
    static let trafficGreen = Color(hex: 0x28C840)

    // MARK: - Surfaces

    static let surface = Color(hex: 0x1A102B)
    static let highlight = Color(hex: 0x29124A)
    static let capFill = Color(hex: 0x2A1152)

    // MARK: - Accent ramp

    static let accent = Color(hex: 0x9333EA)
    static let accentBright = Color(hex: 0xAD66FF)
    static let accentLabel = Color(hex: 0xBFADFF)
    static let accentSoft = Color(hex: 0xB79CFF)
    static let accentPale = Color(hex: 0xC9B6FF)
    static let accentMark = Color(hex: 0xA98CFF)
    static let accentRose = Color(hex: 0xBF8FFF)
    static let accentLavender = Color(hex: 0xD3BCFF)
    static let accentLavenderSoft = Color(hex: 0xD3C8FC)
    static let accentMauve = Color(hex: 0xA897CD)
    static let accentFaint = Color(hex: 0x8B7BB8)

    /// Node 2:463 "Save Btn" — a hair warmer than `accent`, and used only for that one fill.
    static let accentSave = Color(hex: 0x9433EB)

    // MARK: - Type

    static let textPrimary = Color(hex: 0xE8E6F5)
    static let textMuted = Color(hex: 0x6E6E8C)
    static let textMutedBright = Color(hex: 0x8C8CA8)
    static let textSoft = Color(hex: 0xD3D3E0)
    static let textCool = Color(hex: 0xA8A8C2)

    // MARK: - Semantics

    static let success = Color(hex: 0x22C55E)
    static let danger = Color(hex: 0xFF4D6D)
    static let dangerFill = Color(hex: 0xFF4D6E)
    static let warning = Color(hex: 0xFFBD2D)
    static let info = Color(hex: 0x7DA8E8)
    static let halo = Color(hex: 0x2EA7FF)
}
