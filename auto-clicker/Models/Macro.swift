//
//  Macro.swift
//  auto-clicker
//
//  The macro model backing the "TriggerPilot" window. The design file describes a macro as a
//  name, an ordered list of key caps and a trigger mode, plus three optional settings that the
//  settings panel exposes (repeat count, start delay and inter-key interval).
//

import Defaults
import Foundation

/// How a macro's key combination is delivered.
enum TriggerMode: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case simultaneous
    case sequential
    case longPress

    var id: String { self.rawValue }

    var localised: String {
        switch self {
        case .simultaneous: return "macro_mode_simultaneous"
        case .sequential: return "macro_mode_sequential"
        case .longPress: return "macro_mode_long_press"
        }
    }
}

/// A single key cap in a macro's combination, e.g. `CMD`, `S` or a mouse button.
struct KeyCap: Codable, Hashable, Defaults.Serializable {
    var label: String

    /// Renders in the amber accent colour. The design uses this to flag the "real" key in a
    ///  combination that is otherwise made up of modifiers.
    var isAccent: Bool

    /// The virtual key code the cap stands for.
    ///
    /// Captured caps carry the real code the user pressed. The seed data leaves it at zero, in
    ///  which case the code is resolved from the label instead — a captured code is always exact,
    ///  whereas a label lookup only covers the keys the table knows about.
    var keyCode: UInt16

    /// The mouse button this cap stands for, or `nil` when the cap is a keyboard key.
    ///
    /// A combination can mix the two, e.g. Cmd plus a right click, so this is a property of the cap
    ///  rather than a separate kind of slot.
    var mouseButton: Int?

    init(_ label: String, isAccent: Bool = false, keyCode: UInt16 = 0, mouseButton: Int? = nil) {
        self.label = label
        self.isAccent = isAccent
        self.keyCode = keyCode
        self.mouseButton = mouseButton
    }

    /// Builds a cap from a mouse button number: 0 left, 1 right, 2 middle, 3 and up the side buttons.
    init(mouseButton: Int) {
        self.label = KeyCap.mouseLabel(for: mouseButton)
        self.isAccent = true
        self.keyCode = 0
        self.mouseButton = mouseButton
    }
}

extension KeyCap {
    /// Hand rolled so that adding `keyCode` and `mouseButton` cannot invalidate caps an existing user
    ///  already has: `Defaults` falls back to the key's default value when stored JSON fails to
    ///  decode, and `Macro` decodes its whole cap array in one go, so a throw here would wipe every
    ///  cap.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.isAccent = try container.decodeIfPresent(Bool.self, forKey: .isAccent) ?? false
        self.keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? 0
        self.mouseButton = try container.decodeIfPresent(Int.self, forKey: .mouseButton)
    }

    private enum CodingKeys: String, CodingKey {
        case label, isAccent, keyCode, mouseButton
    }
}

extension KeyCap {
    /// Short Latin labels, matching the style of the design's own `CMD` and `SHF` caps.
    static func mouseLabel(for button: Int) -> String {
        switch button {
        case 0: return "LMB"
        case 1: return "RMB"
        case 2: return "MMB"
        default: return "MB\(button)"
        }
    }

    /// The modifier this cap stands for, or `nil` when the cap is a regular key or a mouse button.
    var modifier: Input.Modifier? {
        guard self.mouseButton == nil else {
            return nil
        }

        switch self.label.uppercased() {
        case "CMD", "⌘": return .command
        case "SHF", "⇧": return .shift
        case "OPT", "⌥": return .option
        case "CTL", "^": return .control
        default: return nil
        }
    }

    /// Whether the cap only modifies the event rather than producing one of its own.
    var isModifier: Bool { self.modifier != nil }

    /// The event this cap produces, with the combination's other caps passed in as modifiers.
    func input(withModifiers modifiers: [Input.Modifier]) -> Input {
        if let button = self.mouseButton {
            return Input(mouseButton: button, modifiers: modifiers)
        }

        return Input(readable: self.label,
                     type: .keyDown,
                     keyCode: self.resolvedKeyCode,
                     modifiers: modifiers,
                     isMouseInput: false,
                     isRepeat: false)
    }

    /// The virtual key code to press, preferring a captured code over the label table.
    var resolvedKeyCode: UInt16 {
        if self.keyCode != 0 {
            return self.keyCode
        }

        return Self.virtualKeyCodes[self.label.uppercased()] ?? 0
    }

    /// Carbon virtual key codes, keyed by the cap label. Covers everything the design's seed data
    ///  uses plus the keys the capture flow can produce without a stored code.
    static let virtualKeyCodes: [String: UInt16] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33,
        "I": 34, "P": 35, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "N": 45, "M": 46, ".": 47,
        "↩": 36, "⇥": 48, "⎵": 49, "⌫": 51, "⎋": 53,
        "→": 124, "←": 123, "↓": 125, "↑": 126
    ]
}

struct Macro: Codable, Identifiable, Hashable, Defaults.Serializable {
    var id: UUID
    var name: String
    var caps: [KeyCap]
    var mode: TriggerMode
    var repeatCount: Int
    var delayEnabled: Bool
    var delaySeconds: Double

    /// Milliseconds between each key in `.sequential` mode.
    var intervalMilliseconds: Int

    /// Milliseconds between two consecutive rounds of the whole combination.
    ///
    /// This is the one timing every mode shares: a chord has nothing to space out internally, and a
    ///  long press only has its hold, but all three modes repeat. It used to be the simulator's
    ///  fixed 1ms tick, which made the rounds run back to back with no way to slow them down.
    var roundIntervalMilliseconds: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, caps, mode, repeatCount, delayEnabled, delaySeconds, intervalMilliseconds
        case roundIntervalMilliseconds
    }
}

extension Macro {
    static let maxCaps = 5

    /// Bounds on the repeat count. The upper limit exists so that a mistyped number cannot ask the
    ///  simulator for a run that would never end.
    static let minRepeatCount = 1
    static let maxRepeatCount = 9999

    init(name: String, caps: [KeyCap], mode: TriggerMode, repeatCount: Int = 1,
         delayEnabled: Bool = false, delaySeconds: Double = 1.5, intervalMilliseconds: Int = 300,
         roundIntervalMilliseconds: Int = 300) {
        self.id = UUID()
        self.name = name
        self.caps = caps
        self.mode = mode
        self.repeatCount = repeatCount
        self.delayEnabled = delayEnabled
        self.delaySeconds = delaySeconds
        self.intervalMilliseconds = intervalMilliseconds
        self.roundIntervalMilliseconds = roundIntervalMilliseconds
    }
}

extension Macro {
    /// Hand rolled for the same reason as `FormState` — `Defaults` falls back to the key's default
    ///  value when stored JSON fails to decode, so a missing key must not throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.caps = try container.decodeIfPresent([KeyCap].self, forKey: .caps) ?? []
        self.mode = try container.decodeIfPresent(TriggerMode.self, forKey: .mode) ?? .simultaneous
        self.repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        self.delayEnabled = try container.decodeIfPresent(Bool.self, forKey: .delayEnabled) ?? false
        self.delaySeconds = try container.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 1.5
        self.intervalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .intervalMilliseconds) ?? 300
        self.roundIntervalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .roundIntervalMilliseconds) ?? 300
    }

    /// The `"4 键"` badge shown at the trailing edge of a macro row.
    var keyCountText: String {
        String(format: NSLocalizedString("macro_key_count", comment: "Macro key count"), self.caps.count)
    }
}

extension Macro {
    /// Translates the macro's caps into the event list `AutoClickSimulator` presses.
    ///
    /// The design stores a combination as one cap per key, and `mode` decides how those caps are
    ///  delivered:
    ///
    ///  - `simultaneous` collects the modifiers into a single event's flags and presses the one
    ///    non-modifier cap, which is the usual "hold Cmd+Shift and tap S" chord. A chord has exactly
    ///    one key, so a combination holding two or more of them has no well defined meaning and is
    ///    refused rather than having its extra keys dropped.
    ///  - `sequential` emits one event per cap, so the caps are pressed in the order they are drawn,
    ///    spaced by `intervalMilliseconds`. This is also what makes an all-modifier combination
    ///    meaningful, since a chord of only modifiers has no key to press.
    ///  - `longPress` is a chord that is held: the same single event as `simultaneous`, with the
    ///    hold applied by the simulator's `holdInterval`.
    var pressInputs: [Input] {
        switch self.mode {
        case .sequential:
            // Each cap stands alone, so a modifier cap is pressed as its own event and a mouse cap
            //  becomes its own click. The combination's modifiers still ride along on every cap that
            //  is not itself a modifier, which is what makes a recorded Cmd+click behave like one.
            let modifiers = self.caps.compactMap(\.modifier)

            return self.caps.map { cap in
                cap.input(withModifiers: cap.isModifier ? [] : modifiers)
            }

        case .simultaneous, .longPress:
            // `unsupportedReason` reports the two shapes that have no key to press, so reaching
            //  this point with no key would mean the caller skipped that check.
            guard let key = self.plainKeys.first ?? self.caps.first(where: { !$0.isModifier }) else {
                return []
            }

            let modifiers = self.caps.compactMap(\.modifier)

            return [key.input(withModifiers: modifiers)]
        }
    }

    /// The macro's regular keys, i.e. everything that is neither a modifier nor a mouse button.
    var plainKeys: [KeyCap] {
        self.caps.filter { !$0.isModifier && $0.mouseButton == nil }
    }

    /// Why the macro cannot be run as configured, or `nil` when it can.
    ///
    /// A combination is stored as one cap per key, and each mode can only deliver certain shapes.
    ///  Checking here rather than silently dropping the surplus is what stops a macro that the
    ///  panel accepts from doing something other than what its name describes.
    var unsupportedReason: String? {
        switch self.mode {
        case .simultaneous:
            // A chord presses one key with the modifiers held, so it can only carry one key.
            return self.plainKeys.count > 1 ? "macro_error_simultaneous_multi_key" : nil
        case .sequential:
            return self.caps.isEmpty ? "macro_error_no_key" : nil
        case .longPress:
            return self.caps.isEmpty ? "macro_error_no_key" : nil
        }
    }

    /// The macro expressed in the terms `AutoClickSimulator` already understands.
    ///
    /// Built as an override rather than written into `Defaults[.autoClickerState]` so that running a
    ///  macro cannot clobber the interval and input the user configured on the settings tab.
    var pressState: FormState {
        var state = FormState()

        state.pressInputs = self.pressInputs
        // One press per tick; the repetition is expressed through `repeatAmount`.
        state.pressAmount = 1
        state.repeatAmount = max(1, self.repeatCount)
        state.startDelay = self.delayEnabled ? max(0, Int(self.delaySeconds.rounded())) : 0

        // Every mode repeats whole rounds, so the gap between rounds is the one timing all three
        //  share. It is what the simulator's timer is scheduled on.
        state.pressInterval = max(1, self.roundIntervalMilliseconds)

        switch self.mode {
        case .sequential:
            // The interval slider is the gap between the keys *within* one round, so it goes to the
            //  inter-key delay instead. The two sliders are independent: one paces a round, the
            //  other paces the rounds.
            state.pressInputInterval = max(1, self.intervalMilliseconds)
            state.holdInterval = nil

        case .simultaneous:
            // A chord is a single event, so there is nothing to space out inside a round.
            state.pressInputInterval = nil
            state.holdInterval = nil

        case .longPress:
            // The design labels this mode "长按 2 秒", so the hold stays fixed at two seconds while
            //  the rounds themselves follow the round gap.
            state.pressInputInterval = nil
            state.holdInterval = LONG_PRESS_HOLD_INTERVAL
        }

        state.pressIntervalDuration = .milliseconds

        return state
    }
}

extension Macro {
    /// Seed data mirroring the five macros drawn in the design file.
    static var seed: [Macro] {
        [
            Macro(name: NSLocalizedString("macro_seed_1_name", comment: "Seed macro 1"),
                  caps: [KeyCap("CMD"), KeyCap("SHF"), KeyCap("S"), KeyCap("3")],
                  // Sequential, not simultaneous: a chord presses exactly one key, so this
                  //  combination could only ever deliver Cmd+Shift+S and would drop the 3.
                  mode: .sequential),
            Macro(name: NSLocalizedString("macro_seed_2_name", comment: "Seed macro 2"),
                  caps: [KeyCap("CMD"), KeyCap("OPT")],
                  mode: .sequential),
            Macro(name: NSLocalizedString("macro_seed_3_name", comment: "Seed macro 3"),
                  caps: [KeyCap("CMD"), KeyCap("SHF"), KeyCap("K")],
                  mode: .sequential),
            Macro(name: NSLocalizedString("macro_seed_4_name", comment: "Seed macro 4"),
                  caps: [KeyCap("CTL"), KeyCap("OPT"), KeyCap("M"), KeyCap("R"), KeyCap("5", isAccent: true)],
                  mode: .sequential),
            Macro(name: NSLocalizedString("macro_seed_5_name", comment: "Seed macro 5"),
                  caps: [KeyCap("CMD"), KeyCap("N"), KeyCap("P"), KeyCap("F")],
                  mode: .sequential),
        ]
    }
}
