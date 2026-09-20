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

    enum Modifier: String, Codable {
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
        switch mouseButton {
        case 1:
            self.readable = "RMB"
            self.type = .rightMouseDown
        case 2:
            self.readable = "MMB"
            self.type = .otherMouseDown
        default:
            self.readable = "LMB"
            self.type = .leftMouseDown
        }

        self.keyCode = UInt16(max(0, mouseButton))
        self.modifiers = modifiers
        self.isMouseInput = true
        self.isRepeat = false
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
