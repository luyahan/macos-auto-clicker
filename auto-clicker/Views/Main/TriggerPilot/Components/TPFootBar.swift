//
//  TPFootBar.swift
//  auto-clicker
//
//  Node 2:319 "Foot Bar" — a 48pt bar at 3% white. The "新建宏" button stretches to 274pt in the
//  design, which is expressed here as a fixed width so the status pill keeps its position.
//
//  The button is a menu now: one entry creates the original looping macro, the other creates a
//  one-shot mouse macro. Both keep the design's 274pt footprint.
//

import SwiftUI

struct TPFootBar: View {
    let statusText: String
    let onAdd: (MacroActivation) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    self.onAdd(.repeating)
                } label: {
                    Text("macro_add_repeating", comment: "Add looping macro menu item")
                }

                Button {
                    self.onAdd(.oneShot)
                } label: {
                    Text("macro_add_one_shot", comment: "Add one-shot macro menu item")
                }
            } label: {
                HStack(spacing: 6) {
                    PlusGlyph()
                        .stroke(TPPalette.accentPale, style: TPMetrics.glyphStrokeBold)
                        .frame(width: 12, height: 12)

                    Text("macro_add", comment: "Add macro button")
                        .font(TPType.text(12, weight: .medium))
                        .foregroundColor(TPPalette.textPrimary)

                    Text("▾")
                        .font(TPType.text(10))
                        .foregroundColor(TPPalette.textMuted)
                }
                .frame(width: 274, height: 32)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(width: 274, height: 32)

            HStack(spacing: 6) {
                Circle()
                    .fill(TPPalette.success)
                    .frame(width: 6, height: 6)

                Text(self.statusText)
                    .font(TPType.text(11))
                    .foregroundColor(TPPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TPMetrics.bodyPadding)
        .frame(height: TPMetrics.footBarHeight)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03))
    }
}

struct TPFootBar_Previews: PreviewProvider {
    static var previews: some View {
        TPFootBar(statusText: "监听中", onAdd: { _ in })
            .frame(width: TPMetrics.windowWidth)
            .background(TPPalette.windowBackground)
    }
}
