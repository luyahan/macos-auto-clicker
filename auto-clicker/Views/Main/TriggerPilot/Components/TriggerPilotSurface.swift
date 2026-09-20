//
//  TriggerPilotSurface.swift
//  auto-clicker
//
//  The rounded card both windows are built from.
//
//  Almost every block in the TriggerPilot UI is the same shape: a rounded rectangle filled with a
//  surface colour, optionally outlined by a hairline stroke. Writing that out as a `.background`
//  plus an `.overlay` at each site meant the corner radius, the stroke width and the stroke colour
//  were repeated a dozen times, and any adjustment had to be made in every one of them. The
//  modifier below keeps those three decisions in a single place.
//

import SwiftUI

/// A rounded surface with an optional hairline outline.
struct TriggerPilotSurface: ViewModifier {
    /// `nil` draws the fill only.
    var stroke: Color?

    var cornerRadius: CGFloat
    var fill: Color
    var strokeWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .fill(self.fill)
            )
            .overlay {
                if let stroke = self.stroke {
                    RoundedRectangle(cornerRadius: self.cornerRadius)
                        .stroke(stroke, lineWidth: self.strokeWidth)
                }
            }
    }
}

extension View {
    /// Fills the view with a rounded surface, and optionally outlines it.
    ///
    /// The overlay is attached with `.overlay { }` rather than `.overlay(_:)` so that the outline
    ///  adds no size to the layout, and so that passing `nil` for `stroke` leaves the hierarchy
    ///  unchanged rather than inserting an invisible shape.
    func triggerPilotSurface(
        fill: Color,
        cornerRadius: CGFloat,
        stroke: Color? = nil,
        strokeWidth: CGFloat = 1
    ) -> some View {
        self.modifier(
            TriggerPilotSurface(
                stroke: stroke,
                cornerRadius: cornerRadius,
                fill: fill,
                strokeWidth: strokeWidth
            )
        )
    }

    /// Clips the view to the window's rounded corner and draws the hairline around the edge.
    ///
    /// Both of the app's windows need the clip: the main window's decorative halos are drawn wider
    ///  than the frame and would otherwise square off the corners, and a sheet would paint its
    ///  rectangular backing behind them.
    func triggerPilotWindowOutline(
        cornerRadius: CGFloat,
        stroke: Color = Color.white.opacity(0.06)
    ) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}
