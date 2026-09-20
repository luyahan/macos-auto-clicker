//
//  TriggerPilotGlyphs.swift
//  auto-clicker
//
//  Vector glyphs drawn from the design file. Each one is a `Shape` so it can be stroked with the
//  exact colours and weights the design specifies, which SF Symbols cannot express.
//

import SwiftUI

/// The `<>` app mark in the title bar (node 2:315).
struct AppMarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.36, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.95))

        path.move(to: CGPoint(x: w * 0.64, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.95))

        return path
    }
}

/// A `+` drawn as two strokes (nodes 2:407, 2:451, 6:24).
struct PlusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))

        return path
    }
}

/// A `−` drawn as a single stroke (node 6:22).
struct MinusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))

        return path
    }
}

/// The `×` in the settings panel's close button (node 2:424).
struct CloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        return path
    }
}

/// The circled exclamation mark in the exclusive-notice bar (nodes 2:323–2:325).
struct NoticeGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(TPPalette.accentSoft, lineWidth: 1.2)

            Capsule()
                .fill(TPPalette.accentSoft)
                .frame(width: 1.3, height: 5)
                .offset(y: -1.5)

            Circle()
                .fill(TPPalette.accentSoft)
                .frame(width: 1.6, height: 1.6)
                .offset(y: 3)
        }
    }
}

/// The ringed counter used by the "重复次数" option row (nodes 6:9, 6:10).
struct RepeatGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(TPPalette.accentSoft, style: TPMetrics.glyphStroke)

            PlusGlyph()
                .stroke(TPPalette.accentSoft, lineWidth: 1.3)
                .frame(width: 7, height: 7)
                .offset(x: 4, y: -4)
        }
    }
}

/// The clock used by the "延迟执行" option row (nodes 6:17, 6:18).
struct ClockGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(TPPalette.info, lineWidth: 1.3)

            Path { path in
                path.move(to: CGPoint(x: 7.5, y: 7.5))
                path.addLine(to: CGPoint(x: 7.5, y: 4))
            }
            .stroke(TPPalette.info, style: TPMetrics.glyphStroke)

            Path { path in
                path.move(to: CGPoint(x: 7.5, y: 7.5))
                path.addLine(to: CGPoint(x: 10, y: 9))
            }
            .stroke(TPPalette.info, style: TPMetrics.glyphStroke)
        }
    }
}

/// The interval glyph used by the "依次触发间隔" card (nodes 6:31, 6:32).
struct IntervalGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(TPPalette.accentSoft)
                    .frame(width: 7, height: 1.3)
                    .offset(y: CGFloat(index) * 4.5 - 4.5)
            }

            Circle()
                .stroke(TPPalette.accentSoft, lineWidth: 1.2)
                .frame(width: 3.4, height: 3.4)
                .offset(x: 5, y: -4.5)
        }
    }
}

/// The link glyph in the "随上方「触发方式」联动显示" hint row (nodes 6:45, 6:46).
struct LinkGlyph: View {
    var body: some View {
        ZStack {
            Capsule()
                .stroke(TPPalette.accentFaint, lineWidth: 1.2)
                .frame(width: 8, height: 5)
                .rotationEffect(.degrees(-45))
                .offset(x: -2.5)

            Capsule()
                .stroke(TPPalette.accentFaint, lineWidth: 1.2)
                .frame(width: 8, height: 5)
                .rotationEffect(.degrees(-45))
                .offset(x: 2.5)
        }
    }
}
