//
//  MacroTrigger.swift
//  auto-clicker
//
//  The "one macro loops, several macros fire once" split lives here. A `.repeating` macro keeps the
//  original behaviour (armed exclusively, driven by the global Start/Stop shortcuts). A `.oneShot`
//  macro carries its own trigger and an independent enabled flag, so any number of them can listen
//  at the same time.
//

import AppKit
import Defaults
import KeyboardShortcuts

/// What puts a macro to work.
enum MacroActivation: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    /// The original behaviour: one armed macro, started and stopped globally, repeats N rounds.
    case repeating

    /// Fires exactly one round whenever its own trigger is seen, then stops.
    case oneShot

    var id: String { self.rawValue }

    var localised: String {
        switch self {
        case .repeating: return "macro_activation_repeating"
        case .oneShot: return "macro_activation_one_shot"
        }
    }
}

/// The input that fires a one-shot macro.
///
/// Exactly one of `mouseButton` / `keyCode` is populated. Both are optional so that a preferences
/// file written by an older build — or a half-finished draft — decodes without wiping the macro.
struct MacroTrigger: Codable, Hashable, Defaults.Serializable {
    /// Button numbers follow AppKit: 0 left, 1 right, 2 middle, 3+ side buttons.
    var mouseButton: Int?

    /// Carbon virtual key code for a keyboard trigger.
    var keyCode: UInt16?

    /// The printable label captured for a keyboard trigger, used only for display.
    var keyLabel: String?

    var modifiers: [Input.Modifier]

    static let maxMouseButton = 32

    /// Carbon key codes that are modifiers on their own. A trigger made only of these would fire
    /// every time the user reached for any ordinary shortcut, so they are refused at capture time.
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]

    private static let relevantFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    init(mouseButton: Int, modifiers: [Input.Modifier] = []) {
        self.mouseButton = min(max(mouseButton, 0), Self.maxMouseButton)
        self.keyCode = nil
        self.keyLabel = nil
        self.modifiers = Self.sorted(modifiers)
    }

    init(keyCode: UInt16, keyLabel: String?, modifiers: [Input.Modifier] = []) {
        self.mouseButton = nil
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        self.modifiers = Self.sorted(modifiers)
    }

    /// Equality deliberately ignores `keyLabel`: it is display-only, and two captures of the same
    ///  key must count as the same trigger even if one of them has no stored label.
    static func == (lhs: MacroTrigger, rhs: MacroTrigger) -> Bool {
        lhs.mouseButton == rhs.mouseButton
            && lhs.keyCode == rhs.keyCode
            && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.mouseButton)
        hasher.combine(self.keyCode)
        hasher.combine(self.modifiers)
    }

    private static func sorted(_ modifiers: [Input.Modifier]) -> [Input.Modifier] {
        // Recorded order depends on the order AppKit happens to report flags. Sorting keeps two
        // captures of the same combination equal, which is what duplicate detection compares.
        Array(Set(modifiers)).sorted { $0.rawValue < $1.rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case mouseButton, keyCode, keyLabel, modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.mouseButton = try container.decodeIfPresent(Int.self, forKey: .mouseButton)
        self.keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        self.keyLabel = try container.decodeIfPresent(String.self, forKey: .keyLabel)
        self.modifiers = Self.sorted(
            try container.decodeIfPresent([Input.Modifier].self, forKey: .modifiers) ?? []
        )
    }

    var isValid: Bool {
        self.normalized.isConfigured
    }

    private var isConfigured: Bool {
        self.mouseButton != nil || self.keyCode != nil
    }

    /// Brings stored values into the range the event layer can actually post.
    var normalized: MacroTrigger {
        var result = self
        result.modifiers = Self.sorted(self.modifiers)

        if let button = self.mouseButton {
            result.mouseButton = min(max(button, 0), Self.maxMouseButton)
            result.keyCode = nil
            result.keyLabel = nil
        } else {
            result.mouseButton = nil
        }

        return result
    }

    var shortcutFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()

        if self.modifiers.contains(.command) { flags.insert(.command) }
        if self.modifiers.contains(.control) { flags.insert(.control) }
        if self.modifiers.contains(.option) { flags.insert(.option) }
        if self.modifiers.contains(.shift) { flags.insert(.shift) }

        return flags
    }

    var displayLabel: String {
        let base: String

        if let button = self.mouseButton {
            base = KeyCap.mouseLabel(for: button)
        } else if let label = self.keyLabel, !label.isEmpty {
            base = label
        } else {
            base = "KEY \(self.keyCode ?? 0)"
        }

        let prefix = self.modifiers.map(\.rawValue).joined()
        return prefix.isEmpty ? base : prefix + base
    }

    /// Whether a global event is this trigger. Only "down" events count, so holding a button or a
    /// key does not fire the macro repeatedly.
    func matches(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(Self.relevantFlags) == self.shortcutFlags else {
            return false
        }

        if let button = self.mouseButton {
            let pressed: Int?

            switch event.type {
            case .leftMouseDown: pressed = 0
            case .rightMouseDown: pressed = 1
            case .otherMouseDown: pressed = event.buttonNumber
            default: pressed = nil
            }

            return pressed == button
        }

        if let code = self.keyCode {
            guard event.type == .keyDown, !event.isARepeat else { return false }
            return event.keyCode == code
        }

        return false
    }

    /// A keyboard trigger that duplicates the global Start/Stop shortcut would do two things at
    /// once, so the settings panel refuses it. Comparing public `Shortcut` values avoids depending
    /// on the package's internal Carbon helpers.
    var conflictsWithGlobalShortcut: Bool {
        guard let code = self.keyCode else { return false }

        let names: [KeyboardShortcuts.Name] = [.pressStartButton, .pressStopButton]

        return names.contains { name in
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }

            return shortcut.carbonKeyCode == Int(code)
                && shortcut.modifiers.intersection(Self.relevantFlags) == self.shortcutFlags
        }
    }
}

extension MacroTrigger {
    /// Builds a trigger from the same capture events the key-combination slots use.
    static func captured(from event: NSEvent) -> MacroTrigger? {
        let modifiers = Self.modifiers(from: event.modifierFlags)

        switch event.type {
        case .leftMouseDown:
            return MacroTrigger(mouseButton: 0, modifiers: modifiers)
        case .rightMouseDown:
            return MacroTrigger(mouseButton: 1, modifiers: modifiers)
        case .otherMouseDown:
            return MacroTrigger(mouseButton: event.buttonNumber, modifiers: modifiers)
        case .keyDown:
            let code = event.keyCode
            guard !Self.modifierKeyCodes.contains(code), code != 53 else { return nil }

            return MacroTrigger(keyCode: code,
                                keyLabel: KeyCap.captured(from: event)?.label,
                                modifiers: modifiers)
        default:
            return nil
        }
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> [Input.Modifier] {
        var result: [Input.Modifier] = []

        if flags.contains(.command) { result.append(.command) }
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }

        return result
    }
}
