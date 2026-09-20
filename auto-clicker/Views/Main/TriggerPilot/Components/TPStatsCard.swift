//
//  TPStatsCard.swift
//  auto-clicker
//
//  Created by Luke on 20/09/2025.
//

import SwiftUI

/// A single-pixel vertical rule used to separate items inside the stats card and the
///  settings panel option groups.
struct DividerHairline: View {
    var height: CGFloat = 26
    var opacity: Double = 0.07

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(self.opacity))
            .frame(width: 1, height: self.height)
    }
}

/// The three-up summary strip pinned underneath the macro list.
struct TPStatsCard: View {
    let savedCount: Int
    let activeCount: Int
    let triggeredToday: Int

    var body: some View {
        HStack(spacing: 10) {
            TPStat(
                value: "\(self.savedCount)",
                label: NSLocalizedString("macro_stat_saved", comment: "Saved macro stat"),
                colour: TPPalette.textPrimary
            )

            TPStat(
                value: "\(self.activeCount)",
                label: NSLocalizedString("macro_stat_active", comment: "Active macro stat"),
                colour: TPPalette.accentLabel
            )

            TPStat(
                value: "\(self.triggeredToday)",
                label: NSLocalizedString("macro_stat_triggered", comment: "Triggered today stat"),
                colour: TPPalette.success
            )

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                DividerHairline()
                DividerHairline()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: TPMetrics.statsCardHeight)
        .frame(maxWidth: .infinity)
        .triggerPilotSurface(
            fill: Color.white.opacity(0.04),
            cornerRadius: TPMetrics.statsCardCornerRadius
        )
    }
}

private struct TPStat: View {
    let value: String
    let label: String
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.value)
                .font(TPType.mono(16, weight: .bold))
                .foregroundColor(self.colour)

            Text(self.label)
                .font(TPType.text(10.5))
                .foregroundColor(TPPalette.textMuted)
                .lineLimit(1)
        }
        .frame(width: 108, alignment: .leading)
    }
}

struct TPStatsCard_Previews: PreviewProvider {
    static var previews: some View {
        TPStatsCard(savedCount: 5, activeCount: 1, triggeredToday: 0)
            .frame(width: TPMetrics.windowWidth)
            .padding(.vertical, 20)
            .background(TPPalette.windowBackground)
            .previewLayout(.sizeThatFits)
    }
}
