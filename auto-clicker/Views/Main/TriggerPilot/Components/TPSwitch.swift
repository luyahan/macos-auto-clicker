//
//  TPSwitch.swift
//  auto-clicker
//
//  The design's pill switch. Two sizes appear: 34×20 in the title bar (node 2:310) and 32×19 in
//  the settings panel's "延迟执行" row (node 6:25). Both use a fully rounded track with a white
//  knob inset by 2pt.
//

import SwiftUI

struct TPSwitch: View {
    @Binding var isOn: Bool

    var width: CGFloat = 34
    var height: CGFloat = 20
    var onColour: Color = TPPalette.success
    var onOpacity: Double = 0.9

    private var knobSize: CGFloat {
        self.height - 4
    }

    var body: some View {
        ZStack(alignment: self.isOn ? .trailing : .leading) {
            Capsule()
                .fill(self.isOn ? self.onColour.opacity(self.onOpacity) : Color.white.opacity(0.12))

            Circle()
                .fill(Color.white)
                .frame(width: self.knobSize, height: self.knobSize)
                .padding(2)
        }
        .frame(width: self.width, height: self.height)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.16)) {
                self.isOn.toggle()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(self.isOn ? "1" : "0")
    }
}

/// The macro row's selection indicator (nodes 2:332 "Radio On" and 2:334 "Radio Off").
struct TPRadio: View {
    let isOn: Bool
    var size: CGFloat = 17

    /// Arms or disarms the macro. Tapping the circle deliberately does *not* open the settings
    ///  panel — that is the row's job — so the circle stays a pure toggle.
    var onTap: (() -> Void)?

    var body: some View {
        ZStack {
            if self.isOn {
                Circle()
                    .fill(TPPalette.accent)

                Circle()
                    .stroke(TPPalette.accentRose.opacity(0.9), lineWidth: 1.5)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
            }
        }
        .frame(width: self.size, height: self.size)
        .contentShape(Circle())
        .onTapGesture { self.onTap?() }
        .accessibilityAddTraits(.isButton)
    }
}

struct TPSwitch_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TPSwitch(isOn: .constant(true))
            TPSwitch(isOn: .constant(false))
            TPSwitch(isOn: .constant(true), width: 32, height: 19, onOpacity: 0.85)

            HStack(spacing: 12) {
                TPRadio(isOn: true)
                TPRadio(isOn: false)
            }
        }
        .padding(30)
        .background(TPPalette.windowBackground)
    }
}
