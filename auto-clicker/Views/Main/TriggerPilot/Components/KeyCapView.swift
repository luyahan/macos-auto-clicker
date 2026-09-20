//
//  KeyCapView.swift
//  auto-clicker
//
//  A single key cap. Two variants exist in the design: the compact 20pt-tall cap used inside a
//  macro row (node 2:362) and the 42pt-tall slot used by the settings panel (node 2:441).
//

import SwiftUI

struct KeyCapView: View {
    let cap: KeyCap
    var large: Bool = false

    private var height: CGFloat {
        self.large ? TPMetrics.slotHeight : TPMetrics.capHeight
    }

    private var cornerRadius: CGFloat {
        self.large ? TPMetrics.fieldCornerRadius : TPMetrics.capCornerRadius
    }

    private var horizontalPadding: CGFloat {
        self.large ? 0 : TPMetrics.capPadding
    }

    var body: some View {
        Text(self.cap.label)
            .font(TPType.mono(self.large ? 11 : 10))
            .foregroundColor(self.cap.isAccent ? TPPalette.warning : TPPalette.textPrimary)
            .padding(.horizontal, self.horizontalPadding)
            .frame(minWidth: self.large ? 0 : TPMetrics.capMinWidth)
            .frame(height: self.height)
            .frame(maxWidth: self.large ? .infinity : nil)
            .triggerPilotSurface(
                fill: TPPalette.capFill,
                cornerRadius: self.cornerRadius,
                stroke: TPPalette.accentBright.opacity(self.large ? 0.55 : 0.5)
            )
    }
}

/// The dashed-looking empty slot at the end of the settings panel's slot row (node 2:445).
struct EmptyKeyCapSlot: View {
    var body: some View {
        PlusGlyph()
            .stroke(TPPalette.accentFaint, style: TPMetrics.glyphStrokeBold)
            .frame(width: 13, height: 13)
            .frame(height: TPMetrics.slotHeight)
            .frame(maxWidth: .infinity)
            .triggerPilotSurface(
                fill: Color.white.opacity(0.02),
                cornerRadius: TPMetrics.fieldCornerRadius,
                stroke: TPPalette.accentBright.opacity(0.3)
            )
    }
}

// MARK: - Editable slots

/// One slot of the settings panel's key-combination row.
///
/// The design draws the slots as plain, flat caps, so nothing may be added to them visually: the
///  remove affordance lives in a context menu and the capture prompt is an overlay on the panel
///  rather than chrome inside the slot.
struct EditableKeyCapSlot: View {
    let cap: KeyCap?
    let onCapture: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if let cap {
                KeyCapView(cap: cap, large: true)
            } else {
                EmptyKeyCapSlot()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: TPMetrics.fieldCornerRadius))
        .onTapGesture(perform: self.onCapture)
        .contextMenu {
            if cap != nil {
                Button(NSLocalizedString("macro_slot_replace", comment: "Replace key in slot"),
                       action: self.onCapture)
                Button(NSLocalizedString("macro_slot_remove", comment: "Remove key from slot"),
                       action: self.onRemove)
            } else {
                Button(NSLocalizedString("macro_slot_add", comment: "Add a key to the combination"),
                       action: self.onCapture)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cap?.label ?? NSLocalizedString("macro_slot_empty", comment: "Empty key slot")))
        .accessibilityAddTraits(.isButton)
    }
}

/// An invisible AppKit view that claims first responder status and reports the next key press.
///
/// SwiftUI has no key-capture primitive, and the panel's text field must not be the responder while
///  a slot is being recorded, so the capture is done one level down in AppKit.
struct KeyCaptureField: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        KeyCaptureNSView(onKey: self.onKey, onCancel: self.onCancel)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCaptureNSView else {
            return
        }

        view.onKey = self.onKey
        view.onCancel = self.onCancel
    }
}

private final class KeyCaptureNSView: NSView {
    var onKey: (NSEvent) -> Void
    var onCancel: () -> Void

    init(onKey: @escaping (NSEvent) -> Void, onCancel: @escaping () -> Void) {
        self.onKey = onKey
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    /// Lets the very first click land in the view rather than being spent activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels the capture rather than being recorded as a key.
        if event.keyCode == 53 {
            self.onCancel()
            return
        }

        self.onKey(event)
    }

    /// Mouse buttons are recordable too, so a macro can be armed on a middle click.
    ///
    /// The event is not passed on to `super`, which keeps the click from also reaching whatever is
    ///  underneath the capture overlay.
    override func mouseDown(with event: NSEvent) { self.onKey(event) }

    override func rightMouseDown(with event: NSEvent) { self.onKey(event) }

    override func otherMouseDown(with event: NSEvent) { self.onKey(event) }

    /// Swallows the system beep that an unhandled key would otherwise produce.
    override func doCommand(by selector: Selector) {}
}

// MARK: - Key translation

extension KeyCap {
    /// Builds a cap from a captured key press or mouse click.
    ///
    /// The design's caps are one label per key (`CMD`, `SHF`, `S`, `3`), so a press maps to a single
    ///  cap: modifier keys produce their abbreviation and everything else produces its uppercased
    ///  character. The real virtual key code travels with the cap so that playback presses exactly
    ///  the key the user recorded, whatever its label looks like.
    static func captured(from event: NSEvent) -> KeyCap? {
        // Mouse buttons are checked first: their events carry no key code, so the keyboard branch
        //  below would reject them.
        switch event.type {
        case .leftMouseDown, .leftMouseUp: return KeyCap(mouseButton: 0)
        case .rightMouseDown, .rightMouseUp: return KeyCap(mouseButton: 1)
        case .otherMouseDown, .otherMouseUp: return KeyCap(mouseButton: event.buttonNumber)
        default: break
        }

        let code = event.keyCode

        switch code {
        case 55, 54: return KeyCap("CMD", keyCode: code)
        case 56, 60: return KeyCap("SHF", keyCode: code)
        case 58, 61: return KeyCap("OPT", keyCode: code)
        case 59, 62: return KeyCap("CTL", keyCode: code)
        case 57: return KeyCap("CAP", isAccent: true, keyCode: code)
        default: break
        }

        guard let characters = event.charactersIgnoringModifiers,
              let first = characters.first,
              !first.isWhitespace,
              first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol
        else {
            return nil
        }

        return KeyCap(String(first).uppercased(), isAccent: true, keyCode: code)
    }
}

struct KeyCapView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            HStack(spacing: TPMetrics.capSpacing) {
                KeyCapView(cap: KeyCap("CMD"))
                KeyCapView(cap: KeyCap("SHF"))
                KeyCapView(cap: KeyCap("5", isAccent: true))
            }

            HStack(spacing: TPMetrics.slotSpacing) {
                KeyCapView(cap: KeyCap("CMD"), large: true)
                EmptyKeyCapSlot()
            }
            .frame(width: 200)
        }
        .padding(24)
        .background(TPPalette.windowBackground)
    }
}
