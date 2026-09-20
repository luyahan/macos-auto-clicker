//
//  FormState.swift
//  auto-clicker
//
//  Created by Ben Tindall on 10/04/2022.
//

import Defaults

enum IntervalMode: String, Codable, CaseIterable, Identifiable {
    case staticInterval
    case rangeInterval

    var id: String { self.rawValue }
}

struct FormState: Codable, Defaults.Serializable {
    var intervalMode: IntervalMode // new: static or range
    var pressInterval: Int
    var pressIntervalMin: Int? // new: for range
    var pressIntervalMax: Int? // new: for range
    var pressIntervalDuration: Duration

    /// How long the simulator holds a combination down before releasing it, in milliseconds.
    ///
    /// Only a macro in `.longPress` mode sets this; the legacy settings tab leaves it `nil`, and
    ///  `nil` means the release is not deferred at all. Kept optional so that a stored form state
    ///  written before this field existed still decodes.
    var holdInterval: Int?

    /// Milliseconds between the inputs of a *single* press cycle.
    ///
    /// A macro's "依次触发间隔" slider writes here rather than to `pressInterval`, because that one
    ///  schedules the next round of the whole combination: a macro set to 2s used to fire its keys
    ///  100ms apart and then wait two seconds before the next round, which is not what the panel's
    ///  "仅依次触发时生效" hint describes. `nil` keeps the legacy fixed 100ms.
    var pressInputInterval: Int?

    var pressInputs: [Input] // new: one or more inputs, pressed in order
    var pressAmount: Int
    var startDelay: Int
    var repeatAmount: Int

    private enum CodingKeys: String, CodingKey {
        case intervalMode, pressInterval, pressIntervalMin, pressIntervalMax, pressIntervalDuration
        case holdInterval
        case pressInputInterval
        case pressInputs
        case pressInput // legacy, pre-multi-input
        case pressAmount, startDelay, repeatAmount
    }
}

extension FormState {
    init() {
        self.intervalMode = .staticInterval
        self.pressInterval = DEFAULT_PRESS_INTERVAL
        self.pressIntervalMin = nil
        self.pressIntervalMax = nil
        self.pressIntervalDuration = Duration.milliseconds
        self.holdInterval = nil
        self.pressInputInterval = nil
        self.pressInputs = [Input()]
        self.pressAmount = DEFAULT_PRESS_AMOUNT
        self.startDelay = DEFAULT_START_DELAY
        self.repeatAmount = DEFAULT_REPEAT_AMOUNT
    }
}

extension FormState {
    // Hand rolled so that a change in shape cannot nuke an existing user's whole form state, as
    //   `Defaults` silently falls back to the key's default value when the stored JSON fails to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.intervalMode = try container.decodeIfPresent(IntervalMode.self, forKey: .intervalMode) ?? .staticInterval
        self.pressInterval = try container.decodeIfPresent(Int.self, forKey: .pressInterval) ?? DEFAULT_PRESS_INTERVAL
        self.pressIntervalMin = try container.decodeIfPresent(Int.self, forKey: .pressIntervalMin)
        self.pressIntervalMax = try container.decodeIfPresent(Int.self, forKey: .pressIntervalMax)
        self.pressIntervalDuration = try container.decodeIfPresent(Duration.self, forKey: .pressIntervalDuration) ?? .milliseconds
        self.holdInterval = try container.decodeIfPresent(Int.self, forKey: .holdInterval)
        self.pressInputInterval = try container.decodeIfPresent(Int.self, forKey: .pressInputInterval)

        let inputs = try container.decodeIfPresent([Input].self, forKey: .pressInputs)?.filter { !$0.readable.isEmpty } ?? []

        if !inputs.isEmpty {
            self.pressInputs = inputs
        } else if let legacyInput = try container.decodeIfPresent(Input.self, forKey: .pressInput) {
            self.pressInputs = [legacyInput]
        } else {
            self.pressInputs = [Input()]
        }

        self.pressAmount = try container.decodeIfPresent(Int.self, forKey: .pressAmount) ?? DEFAULT_PRESS_AMOUNT
        self.startDelay = try container.decodeIfPresent(Int.self, forKey: .startDelay) ?? DEFAULT_START_DELAY
        self.repeatAmount = try container.decodeIfPresent(Int.self, forKey: .repeatAmount) ?? DEFAULT_REPEAT_AMOUNT
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.intervalMode, forKey: .intervalMode)
        try container.encode(self.pressInterval, forKey: .pressInterval)
        try container.encodeIfPresent(self.pressIntervalMin, forKey: .pressIntervalMin)
        try container.encodeIfPresent(self.pressIntervalMax, forKey: .pressIntervalMax)
        try container.encode(self.pressIntervalDuration, forKey: .pressIntervalDuration)
        try container.encodeIfPresent(self.holdInterval, forKey: .holdInterval)
        try container.encodeIfPresent(self.pressInputInterval, forKey: .pressInputInterval)
        try container.encode(self.pressInputs, forKey: .pressInputs)
        try container.encode(self.pressAmount, forKey: .pressAmount)
        try container.encode(self.startDelay, forKey: .startDelay)
        try container.encode(self.repeatAmount, forKey: .repeatAmount)
    }
}
