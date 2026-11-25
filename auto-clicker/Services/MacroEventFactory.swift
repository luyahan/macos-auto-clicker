//
//  MacroEventFactory.swift
//  auto-clicker
//
//  Stateless CGEvent construction, shared by the looping simulator and the independent one-shot
//  runs. Keeping this in one place is what stops the two execution paths from drifting apart on
//  side-button numbering, modifier flags or long-press releases.
//

import AppKit

enum MacroEventFactory {
    private static let mouseDownTypes: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseDown, .leftMouseUp: .leftMouseDown,
        .rightMouseDown: .rightMouseDown, .rightMouseUp: .rightMouseDown,
        .otherMouseDown: .otherMouseDown, .otherMouseUp: .otherMouseDown
    ]

    private static let mouseUpTypes: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseUp, .leftMouseUp: .leftMouseUp,
        .rightMouseDown: .rightMouseUp, .rightMouseUp: .rightMouseUp,
        .otherMouseDown: .otherMouseUp, .otherMouseUp: .otherMouseUp
    ]

    private static let mouseButtons: [NSEvent.EventType: CGMouseButton] = [
        .leftMouseDown: .left, .leftMouseUp: .left,
        .rightMouseDown: .right, .rightMouseUp: .right,
        .otherMouseDown: .center, .otherMouseUp: .center
    ]

    /// The cursor position in the CoreGraphics coordinate space (top-left origin).
    private static var cursorPoint: CGPoint {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: screenHeight - location.y)
    }

    static func modifierFlags(for input: Input) -> CGEventFlags {
        var flags = CGEventFlags()

        if input.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if input.modifiers.contains(.control) { flags.insert(.maskControl) }
        if input.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if input.modifiers.contains(.shift) { flags.insert(.maskShift) }

        // A modifier recorded as its own sequential cap still has to be applied as a flag.
        switch input.keyCode {
        case 55, 54: flags.insert(.maskCommand)
        case 56, 60: flags.insert(.maskShift)
        case 58, 61: flags.insert(.maskAlternate)
        case 59, 62: flags.insert(.maskControl)
        default: break
        }

        return flags
    }

    /// Side buttons travel as `otherMouse` events with their real button number in `keyCode`.
    private static func button(for input: Input) -> CGMouseButton {
        guard let mapped = Self.mouseButtons[input.type] else { return .left }
        guard mapped == .center, input.keyCode > 2 else { return mapped }

        return CGMouseButton(rawValue: UInt32(input.keyCode)) ?? mapped
    }

    /// Down/up pair for one press, or an empty array when the stored type is unknown.
    static func pressEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        if input.isMouseInput {
            return Self.mouseClickEvents(source: source, input: input)
        }

        return Self.keyPressEvents(source: source, input: input)
    }

    /// The release half of a held press. Always posted on cancellation too.
    static func releaseEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        if input.isMouseInput {
            return Self.mouseReleaseEvents(source: source, input: input)
        }

        return Self.keyReleaseEvents(source: source, input: input)
    }

    private static func mouseClickEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let downType = Self.mouseDownTypes[input.type],
              let upType = Self.mouseUpTypes[input.type] else {
            return []
        }

        let point = Self.cursorPoint
        let button = Self.button(for: input)

        let mouseDown = CGEvent(mouseEventSource: source,
                                mouseType: downType,
                                mouseCursorPosition: point,
                                mouseButton: button)
        let mouseUp = CGEvent(mouseEventSource: source,
                              mouseType: upType,
                              mouseCursorPosition: point,
                              mouseButton: button)

        let flags = Self.modifierFlags(for: input)
        mouseDown?.flags = flags
        mouseUp?.flags = flags

        return [mouseDown, mouseUp].compactMap { $0 }
    }

    private static func keyPressEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        let keyDown = CGEvent(keyboardEventSource: source,
                              virtualKey: CGKeyCode(input.keyCode),
                              keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source,
                            virtualKey: CGKeyCode(input.keyCode),
                            keyDown: false)

        let flags = Self.modifierFlags(for: input)
        keyDown?.flags = flags
        keyUp?.flags = flags

        return [keyDown, keyUp].compactMap { $0 }
    }

    private static func keyReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(input.keyCode),
                                  keyDown: false) else {
            return []
        }

        keyUp.flags = Self.modifierFlags(for: input)
        return [keyUp]
    }

    private static func mouseReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let upType = Self.mouseUpTypes[input.type],
              let mouseUp = CGEvent(mouseEventSource: source,
                                    mouseType: upType,
                                    mouseCursorPosition: Self.cursorPoint,
                                    mouseButton: Self.button(for: input)) else {
            return []
        }

        mouseUp.flags = Self.modifierFlags(for: input)
        return [mouseUp]
    }
}
