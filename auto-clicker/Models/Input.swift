//
//  Input.swift
//  auto-clicker
//
//  Created by Ben Tindall on 09/04/2022.
//

import SwiftUI
import Defaults

struct Input: Codable, Defaults.Serializable, Hashable {
    var readable: String
    var type: NSEvent.EventType
    var keyCode: UInt16
    var modifiers: [Modifier] = []
    var isMouseInput: Bool
    var isRepeat: Bool

    enum Modifier: String, Codable, Hashable {
        case command = "⌘",
             control = "^",
             option = "⌥",
             shift = "⇧"
    }
}

extension Input {
    init() {
        self.readable = "Left Click"
        self.type = .leftMouseDown
        self.keyCode = 0
        self.modifiers = []
        self.isMouseInput = true
        self.isRepeat = false
    }
}

extension Input {
    /// A mouse click for the macro layer.
    ///
    /// The `type` has to be one of the six types `AutoClickSimulator`'s mouse event maps know about,
    ///  because those maps are force unwrapped when the click is generated. The button number is
    ///  carried in `keyCode` so that the side buttons can be told apart — they all report as
    ///  `otherMouse` and the type alone cannot distinguish them.
    init(mouseButton: Int, modifiers: [Modifier] = []) {
        // Button numbers follow AppKit: 0 left, 1 right, 2 middle, 3+ side buttons.
        // Anything outside a sane range is clamped rather than trapping on UInt16 conversion.
        let button = min(max(mouseButton, 0), Int(UInt16.max))

        switch button {
        case 0:
            self.readable = "LMB"
            self.type = .leftMouseDown
        case 1:
            self.readable = "RMB"
            self.type = .rightMouseDown
        default:
            self.readable = KeyCap.mouseLabel(for: button)
            self.type = .otherMouseDown
        }

        self.keyCode = UInt16(button)
        self.modifiers = modifiers
        self.isMouseInput = true
        self.isRepeat = false
    }

    /// Whether this input can be turned into a `CGEvent` by the simulator.
    ///
    /// Stored state may come from an older version or a hand-edited preferences file, so the
    /// simulator must not force-unwrap its event-type maps or build an event from an unknown type.
    var isValidForExecution: Bool {
        if self.isMouseInput {
            return [.leftMouseDown, .leftMouseUp,
                    .rightMouseDown, .rightMouseUp,
                    .otherMouseDown, .otherMouseUp].contains(self.type)
                && self.keyCode <= 64
        }

        return self.type == .keyDown || self.type == .keyUp
    }
}

extension Input {
    init(_ event: NSEvent) {
        self.readable = event.inputString
        self.type = event.type
        self.isMouseInput = event.isMouseInput

        self.keyCode = event.isMouseInput ? 0 : event.keyCode
        self.isRepeat = event.isMouseInput ? false : event.isARepeat

        guard !event.isMouseInput else {
            return
        }

        if event.modifierFlags.contains(.command) {
            self.modifiers.append(.command)
        }

        if event.modifierFlags.contains(.control) {
            self.modifiers.append(.control)
        }

        if event.modifierFlags.contains(.option) {
            self.modifiers.append(.option)
        }

        if event.modifierFlags.contains(.shift) {
            self.modifiers.append(.shift)
        }
    }
}
