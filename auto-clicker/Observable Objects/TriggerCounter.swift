//
//  TriggerCounter.swift
//  auto-clicker
//
//  Counts how many times a macro has fired today.
//
//  The stats card's third figure is a live value, so it cannot be the constant the design mock
//  shows. It is deliberately not part of `MacroStore`: that store owns the macro list, whereas this
//  counter is written by the simulator on every press cycle, and routing that through the store
//  would publish a macro-list change on every single tick.
//
//  The count resets when the calendar day changes. That is checked both when a press is recorded
//  and when the window appears, because an app left running overnight would otherwise keep showing
//  yesterday's total until the next press.
//

import Defaults
import Foundation

final class TriggerCounter: ObservableObject {
    static let shared = TriggerCounter()

    /// How many times a macro has fired today.
    @Published private(set) var today: Int = 0

    /// `yyyy-MM-dd` in the user's own calendar, so the rollover happens at their midnight rather
    ///  than at a fixed offset from UTC. `en_US_POSIX` keeps the digits Gregorian if the user's
    ///  locale uses a different numbering system.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter
    }()

    private static var currentDay: String {
        TriggerCounter.dayFormatter.string(from: Date())
    }

    private init() {
        // A stored count only belongs to the day it was recorded on.
        self.rolloverIfNeeded()
        self.today = Defaults[.triggerCountToday]
    }

    /// Discards a stored count that was recorded on an earlier day, and reports whether the day
    ///  changed. Every entry point runs this first so the rollover rule lives in exactly one place.
    @discardableResult
    private func rolloverIfNeeded() -> Bool {
        let day = TriggerCounter.currentDay

        guard Defaults[.triggerCountDay] != day else {
            return false
        }

        Defaults[.triggerCountDay] = day
        Defaults[.triggerCountToday] = 0
        self.today = 0

        return true
    }

    /// Records one macro firing. Called by the simulator once per press cycle.
    func record(_ amount: Int = 1) {
        self.rolloverIfNeeded()

        self.today += amount
        Defaults[.triggerCountToday] = self.today
    }

    /// Rolls the count over when the day has changed. Called when the window appears so that a
    ///  window left open across midnight does not keep showing yesterday's figure.
    func refresh() {
        self.rolloverIfNeeded()
    }
}
