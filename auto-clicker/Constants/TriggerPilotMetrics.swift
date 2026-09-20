//
//  TriggerPilotMetrics.swift
//  auto-clicker
//
//  Geometry constants measured from the Ardot "TriggerPilot" design file (file 727793516651652).
//  Values are point sizes straight from the design so the layout can be diffed against the spec.
//

import Foundation
import SwiftUI

enum TPMetrics {
    // MARK: - Main window (7:1 "Macro Utility Window")

    static let windowWidth: CGFloat = 420
    static let windowHeight: CGFloat = 620
    static let windowCornerRadius: CGFloat = 14

    static let titleBarHeight: CGFloat = 40
    static let trafficLightSize: CGFloat = 11
    static let trafficLightSpacing: CGFloat = 8

    static let bodyPadding: CGFloat = 14
    static let bodySpacing: CGFloat = 14

    static let noticeHeight: CGFloat = 32
    static let noticeCornerRadius: CGFloat = 9
    static let macroRowHeight: CGFloat = 63
    static let macroRowSpacing: CGFloat = 9
    static let macroRowCornerRadius: CGFloat = 12

    static let capHeight: CGFloat = 20
    static let capCornerRadius: CGFloat = 5
    static let capSpacing: CGFloat = 6
    /// Inner horizontal padding of a small key cap (design: 7pt each side).
    static let capPadding: CGFloat = 7
    /// Small key caps never shrink below this width (design: 26pt for 1-character labels).
    static let capMinWidth: CGFloat = 26

    static let statsCardHeight: CGFloat = 59
    static let statsCardCornerRadius: CGFloat = 10
    static let footBarHeight: CGFloat = 48

    // MARK: - Settings panel (2:410 "Macro Settings Panel")

    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 616
    static let panelBodySpacing: CGFloat = 11

    static let fieldCornerRadius: CGFloat = 8
    static let slotHeight: CGFloat = 42
    static let slotSpacing: CGFloat = 7
    static let segmentHeight: CGFloat = 30

    static let optionRowCornerRadius: CGFloat = 9
    static let stepperCornerRadius: CGFloat = 7
    static let buttonCornerRadius: CGFloat = 99

    static let deleteButtonWidth: CGFloat = 92
    static let saveButtonWidth: CGFloat = 172
    static let actionButtonHeight: CGFloat = 34

    // MARK: - Strokes

    /// The weight of the small vector glyphs. The design draws them as thin hairlines, and every
    ///  glyph in the TriggerPilot UI uses the same one, so it is named rather than repeated.
    static let glyphStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round)
    /// The weight of the glyphs that sit next to a label at 12pt or larger.
    static let glyphStrokeMedium = StrokeStyle(lineWidth: 1.4, lineCap: .round)
    /// The app mark and the `+` in the foot bar, which the design draws slightly heavier.
    static let glyphStrokeBold = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
}
