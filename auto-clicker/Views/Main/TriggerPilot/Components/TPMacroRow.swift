//
//  TPMacroRow.swift
//  auto-clicker
//
//  Nodes 2:327–2:331. A selected row carries the accent tint and stroke; the rest are a flat 4%
//  white wash. Rows are 63pt tall with a 12pt radius and 11pt of leading gap to the radio.
//
//  Looping macros keep the radio (mutually exclusive arm). One-shot macros use an independent
//  switch instead, because several of them can be enabled at the same time.
//

import SwiftUI

struct TPMacroRow: View {
    let macro: Macro
    let isSelected: Bool

    /// One-shot rows draw a switch rather than a radio.
    var showsSwitch: Bool = false

    /// Tapping the radio or switch arms or disarms the macro. Kept separate from `onEdit` so that
    ///  hitting the control never pops the settings panel open.
    let onToggleActive: () -> Void

    /// Tapping anywhere else on the row opens the macro's settings panel.
    let onEdit: () -> Void

    private var titleColour: Color {
        self.isSelected ? .white : TPPalette.textPrimary
    }

    private var secondaryColour: Color {
        self.isSelected ? TPPalette.accentLabel : TPPalette.textMuted
    }

    var body: some View {
        HStack(spacing: 11) {
            if self.showsSwitch {
                TPSwitch(
                    isOn: Binding(
                        get: { self.isSelected },
                        set: { _ in self.onToggleActive() }
                    ),
                    width: 28,
                    height: 17
                )
                .frame(width: 17)
            } else {
                TPRadio(isOn: self.isSelected, onTap: self.onToggleActive)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(self.macro.name)
                        .font(TPType.text(13, weight: .medium))
                        .foregroundColor(self.titleColour)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if self.macro.activation == .oneShot, let trigger = self.macro.trigger {
                        Text(trigger.displayLabel)
                            .font(TPType.mono(10))
                            .foregroundColor(TPPalette.accentLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text(self.macro.keyCountText)
                        .font(TPType.text(11, weight: self.isSelected ? .medium : .regular))
                        .foregroundColor(self.secondaryColour)
                        .lineLimit(1)
                }

                HStack(spacing: TPMetrics.capSpacing) {
                    ForEach(Array(self.macro.caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapView(cap: cap)
                    }

                    Text(LocalizedStringKey(self.macro.mode.localised))
                        .font(TPType.text(11))
                        .foregroundColor(self.secondaryColour)
                        .lineLimit(1)
                        .padding(.leading, 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: TPMetrics.macroRowHeight)
        .triggerPilotSurface(
            fill: self.isSelected ? TPPalette.accent.opacity(0.14) : Color.white.opacity(0.04),
            cornerRadius: TPMetrics.macroRowCornerRadius,
            stroke: self.isSelected ? TPPalette.accentBright.opacity(0.42) : .clear
        )
        .contentShape(RoundedRectangle(cornerRadius: TPMetrics.macroRowCornerRadius))
        .onTapGesture(perform: self.onEdit)
        .accessibilityElement(children: .contain)
    }
}

struct TPMacroRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: TPMetrics.macroRowSpacing) {
            TPMacroRow(macro: Macro.seed[0], isSelected: true, onToggleActive: {}, onEdit: {})
            TPMacroRow(macro: Macro.seed[1], isSelected: false, onToggleActive: {}, onEdit: {})
            TPMacroRow(macro: Macro.seed[3], isSelected: false, onToggleActive: {}, onEdit: {})
        }
        .padding(TPMetrics.bodyPadding)
        .frame(width: TPMetrics.windowWidth)
        .background(TPPalette.windowBackground)
    }
}
