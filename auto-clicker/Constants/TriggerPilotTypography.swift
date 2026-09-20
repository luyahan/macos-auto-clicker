//
//  TriggerPilotTypography.swift
//  auto-clicker
//
//  Type ramp from the Ardot "TriggerPilot" design file. The design specifies Inter and
//  JetBrains Mono; neither ships with macOS, so each helper tries the real family first and
//  falls back to the closest system equivalent (SF Pro for Inter, SF Mono for JetBrains Mono)
//  to keep the app self-contained rather than depending on fonts being installed by hand.
//

import SwiftUI

enum TPType {
    static let displayFamily = "Inter"
    static let monoFamily = "JetBrains Mono"

    /// Prose text — falls back to the system font, which on macOS is SF Pro.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        self.font(self.displayFamily, size: size, weight: weight, fallbackDesign: .default)
    }

    /// Key caps, numeric readouts and counters.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        self.font(self.monoFamily, size: size, weight: weight, fallbackDesign: .monospaced)
    }

    /// `Font.custom` silently falls back to the system font when the family is missing, which would
    ///  lose the monospaced look for the JetBrains Mono usages, so the family is checked up front.
    private static func font(_ family: String, size: CGFloat, weight: Font.Weight, fallbackDesign: Font.Design) -> Font {
        guard NSFont(name: family, size: size) != nil else {
            return .system(size: size, weight: weight, design: fallbackDesign)
        }

        return .custom(family, size: size).weight(weight)
    }
}
