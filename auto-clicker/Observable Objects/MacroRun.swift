//
//  MacroRun.swift
//  auto-clicker
//
//  One independent execution of a one-shot macro.
//
//  `AutoClickSimulator` is a singleton with process-wide side effects: menu bar items, start/finish
//  notifications, mouse-movement monitors and a `ProcessInfo` activity. Instantiating it once per
//  one-shot macro would make two runs fight over all of those. This class deliberately owns only
//  its own token, condition and event queue, so any number of one-shot macros can run at once
//  without touching the looping macro's UI state.
//

import AppKit
import ApplicationServices
import Foundation

final class MacroRun {
    let macroID: UUID

    /// Upper bound on how long this run can post events, used to mute the trigger monitor so our
    /// own synthetic down events cannot fire another macro.
    let estimatedDuration: TimeInterval

    private let inputs: [Input]
    private let inputInterval: Int
    private let holdInterval: Int?
    private let targetBundleIdentifier: String?
    private let onFinish: (UUID) -> Void

    private let condition = NSCondition()
    private var token: UInt64 = 0
    private var hasFinished = false
    private let queue: DispatchQueue

    init?(macro: Macro, onFinish: @escaping (UUID) -> Void) {
        let safe = macro.validatedForExecution()

        guard safe.activation == .oneShot, safe.runIssue == nil else { return nil }

        let usableInputs = safe.pressInputs.filter { $0.isValidForExecution }
        guard !usableInputs.isEmpty else { return nil }

        self.macroID = safe.id
        self.inputs = usableInputs
        self.inputInterval = safe.mode == .sequential ? max(1, safe.intervalMilliseconds) : 0
        self.holdInterval = safe.mode == .longPress ? LONG_PRESS_HOLD_INTERVAL : nil
        self.targetBundleIdentifier = safe.executionScope == .application
            ? safe.targetBundleIdentifier
            : nil
        self.onFinish = onFinish
        self.queue = DispatchQueue(label: "com.othyn.auto-clicker.one-shot.\(safe.id.uuidString)",
                                   qos: .userInitiated)

        let gaps = max(0, usableInputs.count - 1) * self.inputInterval
        let hold = self.holdInterval ?? 0
        // 150ms of headroom for event delivery, so suppression never ends mid-post.
        self.estimatedDuration = Double(gaps + hold) / 1_000 + 0.15
    }

    func start() {
        // Strongly captured for the lifetime of the block: the coordinator may drop its reference
        // on stop, and the block still has to release any held input.
        self.queue.async {
            self.execute()
            self.finish()
        }
    }

    func stop() {
        self.condition.lock()
        self.token &+= 1
        self.condition.broadcast()
        self.condition.unlock()

        self.finish()
    }

    /// Called exactly once, whether the run completed, was cancelled, or was refused on the first
    /// permission check. The coordinator uses it to drop its reference.
    private func finish() {
        self.condition.lock()
        guard !self.hasFinished else {
            self.condition.unlock()
            return
        }
        self.hasFinished = true
        self.condition.unlock()

        DispatchQueue.main.async { self.onFinish(self.macroID) }
    }

    private func snapshotToken() -> UInt64 {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.token
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.token == value
    }

    @discardableResult
    private func cancellableSleep(milliseconds: Int, token: UInt64) -> Bool {
        guard milliseconds > 0 else { return self.isCurrent(token) }

        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1_000)

        self.condition.lock()
        defer { self.condition.unlock() }

        while self.token == token, Date() < deadline {
            self.condition.wait(until: deadline)
        }

        return self.token == token
    }

    private func execute() {
        let runToken = self.snapshotToken()

        guard self.canPost(runToken) else { return }

        DispatchQueue.main.async { TriggerCounter.shared.record() }

        let source = CGEventSource(stateID: .hidSystemState)
        let holdsDown = self.holdInterval != nil
        var heldInputs: [Input] = []

        for (index, input) in self.inputs.enumerated() {
            guard self.canPost(runToken) else { break }

            let events = MacroEventFactory.pressEvents(source: source, input: input)

            if holdsDown {
                if let down = events.first {
                    down.post(tap: .cghidEventTap)
                    heldInputs.append(input)
                }
            } else {
                for event in events {
                    guard self.canPost(runToken) else { break }
                    event.post(tap: .cghidEventTap)
                }
            }

            if index < self.inputs.count - 1,
               !self.cancellableSleep(milliseconds: self.inputInterval, token: runToken) {
                break
            }
        }

        if let hold = self.holdInterval, hold > 0 {
            _ = self.cancellableSleep(milliseconds: hold, token: runToken)
        }

        // Held keys and buttons must be released even when the run was cancelled mid-hold.
        for input in heldInputs {
            for event in MacroEventFactory.releaseEvents(source: source, input: input) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func canPost(_ runToken: UInt64) -> Bool {
        guard self.isCurrent(runToken), AXIsProcessTrusted() else { return false }
        return self.targetMatches(self.targetBundleIdentifier)
    }

    /// `NSWorkspace` is main-thread state, so the event queue has to hop for the check.
    private func targetMatches(_ target: String?) -> Bool {
        guard let target else { return true }

        let frontmost: String? = {
            if Thread.isMainThread {
                return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }

            return DispatchQueue.main.sync {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
        }()

        return frontmost == target
    }
}
