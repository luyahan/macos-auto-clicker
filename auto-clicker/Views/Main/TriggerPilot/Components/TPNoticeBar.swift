//
//  TPNoticeBar.swift
//  auto-clicker
//
//  Created by Luke on 20/09/2025.
//

import SwiftUI

/// The thin informational strip that sits between the title bar and the macro list, telling the
///  user that only one macro can be armed at a time.
struct TPNoticeBar: View {
    var body: some View {
        HStack(spacing: 8) {
            NoticeGlyph()
                .frame(width: 13, height: 13)

            Text("macro_exclusive_notice", comment: "Exclusive macro notice")
                .font(TPType.text(11.5))
                .foregroundColor(TPPalette.accentLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: TPMetrics.noticeHeight)
        .frame(maxWidth: .infinity)
        .triggerPilotSurface(
            fill: TPPalette.accentBright.opacity(0.1),
            cornerRadius: TPMetrics.noticeCornerRadius,
            stroke: TPPalette.accentBright.opacity(0.22)
        )
    }
}

struct TPNoticeBar_Previews: PreviewProvider {
    static var previews: some View {
        TPNoticeBar()
            .frame(width: TPMetrics.windowWidth - 28)
            .padding(14)
            .background(TPPalette.windowBackground)
            .previewLayout(.sizeThatFits)
    }
}
