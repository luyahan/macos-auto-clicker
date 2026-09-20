//
//  TPTitleBar.swift
//  auto-clicker
//
//  Node 2:307 "Title Bar" — 420×40, 4% white wash, horizontally centred content. The traffic
//  lights here are drawn by SwiftUI rather than AppKit: the window uses `.hiddenTitleBar`, which
//  leaves AppKit's own buttons inset roughly 20pt from the left, where the design places the
//  content. See `TPWindowConfigurator` for the matching hide of the real buttons.
//

import SwiftUI

/// The strip both of the app's title bars are built from.
///
/// The main window and the settings sheet draw the same 40pt bar with the same 4% white wash, the
///  same traffic lights on the left and a draggable gap in the middle; only the content either side
///  of that gap differs. Sharing the frame keeps the two bars from drifting apart in height,
///  padding or drag behaviour.
struct TPTitleBarChrome<Leading: View, Trailing: View>: View {
    let spacing: CGFloat

    private let leading: Leading
    private let trailing: Trailing

    init(spacing: CGFloat = 12,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.spacing = spacing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: self.spacing) {
            TrafficLights()

            self.leading
                .layoutPriority(1)

            // Hiding the standard window buttons removed the only draggable chrome, so the empty
            //  middle of the title bar becomes the window's drag handle. This is a real sibling in
            //  the HStack rather than a `.background`, because a background view is laid out
            //  *below* the SwiftUI content and would never receive the mouse-down.
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)

            self.trailing
        }
        .padding(.horizontal, TPMetrics.bodyPadding)
        .frame(height: TPMetrics.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04).allowsHitTesting(false))
    }
}

struct TPTitleBar: View {
    @Binding var isEnabled: Bool

    var body: some View {
        TPTitleBarChrome {
            HStack(spacing: 7) {
                AppMarkGlyph()
                    .stroke(TPPalette.accentMark, style: TPMetrics.glyphStrokeBold)
                    .frame(width: 14, height: 14)

                Text("app_title", comment: "Application title")
                    .font(TPType.text(13, weight: .medium))
                    .foregroundColor(TPPalette.textPrimary)
                    .lineLimit(1)
            }
        } trailing: {
            TPSwitch(isOn: self.$isEnabled)
        }
    }
}

/// Nodes 2:311–2:313 — 11pt circles with 8pt gaps. The design's own lights are drawn here and
///  wired to the real window, because `TPWindowConfigurator` hides AppKit's buttons to stop two
///  sets of them appearing on top of each other.
///
/// Actions are performed through `WindowHandle`, never through AppKit's `perform…` methods, which
///  all no-op on a window that has lost `.titled`.
struct TrafficLights: View {
    @State private var isHovering = false

    /// Defaults to driving the hosting window. `MacroSettingsPanel` overrides it so its lights
    ///  affect the sheet instead of the window underneath.
    @Environment(\.performWindowAction) private var performWindowAction

    /// Lets a fixed-size window show its green light as unavailable rather than wiring up an action
    ///  that would do nothing.
    @Environment(\.isWindowActionAvailable) private var isWindowActionAvailable

    var body: some View {
        HStack(spacing: TPMetrics.trafficLightSpacing) {
            self.light(TPPalette.trafficRed, label: "close", action: .close)
            self.light(TPPalette.trafficYellow, label: "miniaturise", action: .miniaturise)
            self.light(TPPalette.trafficGreen, label: "zoom", action: .zoom)
        }
        .frame(width: 49, height: TPMetrics.trafficLightSize)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                self.isHovering = hovering
            }
        }
    }

    private func light(_ colour: Color, label: String, action: WindowAction) -> some View {
        let isAvailable = self.isWindowActionAvailable(action)

        return Button {
            self.performWindowAction(action)
        } label: {
            ZStack {
                Circle()
                    // A fixed-size window has no zoom state, so its light is dimmed to match the
                    //  greyed-out green button a stock macOS window shows in the same situation.
                    .fill(isAvailable ? colour : colour.opacity(0.3))

                // The design draws flat circles, so the symbols only appear on hover. Without
                //  them the drawn lights would be unusable for anyone unfamiliar with the app.
                if self.isHovering && isAvailable {
                    Image(systemName: self.symbol(for: action))
                        .font(.system(size: 5.5, weight: .bold))
                        .foregroundColor(.black.opacity(0.55))
                }
            }
            .frame(width: TPMetrics.trafficLightSize, height: TPMetrics.trafficLightSize)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(Text(label))
    }

    private func symbol(for action: WindowAction) -> String {
        switch action {
        case .close: return "xmark"
        case .miniaturise: return "minus"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

struct TPTitleBar_Previews: PreviewProvider {
    static var previews: some View {
        TPTitleBar(isEnabled: .constant(true))
            .frame(width: TPMetrics.windowWidth)
            .background(TPPalette.windowBackground)
    }
}
