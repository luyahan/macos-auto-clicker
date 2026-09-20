//
//  TPFootBar.swift
//  auto-clicker
//
//  Node 2:319 "Foot Bar" — a 48pt bar at 3% white. The "新建宏" button stretches to 274pt in the
//  design, which is expressed here as a fixed width so the status pill keeps its position.
//

import SwiftUI

struct TPFootBar: View {
    let statusText: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: self.onAdd) {
                HStack(spacing: 6) {
                    PlusGlyph()
                        .stroke(TPPalette.accentPale, style: TPMetrics.glyphStrokeBold)
                        .frame(width: 12, height: 12)

                    Text("macro_add", comment: "Add macro button")
                        .font(TPType.text(12, weight: .medium))
                        .foregroundColor(TPPalette.textPrimary)
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
            .buttonStyle(.plain)

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
        TPFootBar(statusText: "监听中", onAdd: {})
            .frame(width: TPMetrics.windowWidth)
            .background(TPPalette.windowBackground)
    }
}
