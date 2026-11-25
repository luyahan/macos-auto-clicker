//
//  MacroRunCoordinator.swift
//  auto-clicker
//
//  Owns the in-flight one-shot runs and the single global monitor that feeds them.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

/// Registry of one-shot runs. Main-thread confined: the trigger monitor and every UI entry point
/// already deliver there, so no lock is needed around the dictionary.
final class MacroRunCoordinator: ObservableObject {
    static let shared = MacroRunCoordinator()

    @Published private(set) var activeRunCount = 0

    private var runs: [UUID: MacroRun] = [:]

    private init() {}

    /// Fires a one-shot macro once. A second trigger arriving while the same macro is still
    /// running is ignored — that is what stops a held or bouncing button from stacking runs.
    func fire(_ macro: Macro) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.fire(macro) }
            return
        }

        let safe = macro.validatedForExecution()

        guard safe.activation == .oneShot, safe.isEnabled, safe.runIssue == nil,
              AXIsProcessTrusted(), self.runs[safe.id] == nil else {
            return
        }

        if safe.executionScope == .application, safe.targetBundleIdentifier == nil {
            return
        }

        guard let run = MacroRun(macro: safe, onFinish: { [weak self] id in
            self?.runFinished(id)
        }) else {
            return
        }

        self.runs[safe.id] = run
        self.activeRunCount = self.runs.count

        // Synthetic down/up events are visible to the global monitor too. Muting triggers for the
        // estimated run length is what keeps a macro that clicks from re-triggering itself.
        MacroTriggerService.shared.suppress(until: Date().addingTimeInterval(run.estimatedDuration))
        run.start()
    }

    private func runFinished(_ id: UUID) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.runFinished(id) }
            return
        }

        self.runs.removeValue(forKey: id)
        self.activeRunCount = self.runs.count
    }

    func stop(macroID id: UUID) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop(macroID: id) }
            return
        }

        self.runs.removeValue(forKey: id)?.stop()
        self.activeRunCount = self.runs.count
    }

    /// Global Stop, the menu bar item and app termination all land here.
    func stopAll() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stopAll() }
            return
        }

        for run in self.runs.values { run.stop() }
        self.runs.removeAll()
        self.activeRunCount = 0
    }

    func isRunning(_ id: UUID) -> Bool {
        self.runs[id] != nil
    }
}

/// Read-only global listener for one-shot triggers.
///
/// `addGlobalMonitorForEvents` observes events delivered to other applications; it cannot consume
/// them. That is deliberate — pressing a side button still reaches the frontmost app as usual, and
/// the macro is an additional action rather than a hijacked input. Swallowing the event would need
/// a CGEventTap and a much broader permission/robustness story.
final class MacroTriggerService {
    static let shared = MacroTriggerService()

    private var monitor: Any?
    private var isInstalled = false
    private var isSuspended = false
    private var suppressUntil: Date = .distantPast

    private init() {}

    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }

        guard !self.isInstalled else { return }
        self.isInstalled = true

        self.monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop() }
            return
        }

        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        self.isInstalled = false
    }

    /// Global key monitors are only fed while the process is trusted for Accessibility, and TCC can
    ///  be granted after launch. Reinstalling on activation makes the monitor pick up a grant
    ///  without the user having to restart the app.
    func restart() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.restart() }
            return
        }

        self.stop()
        self.start()
    }

    /// The settings panel suspends listening while it is open: recording a trigger must not fire
    /// whatever macro is already armed, and editing a macro should not be interrupted by a run.
    func setSuspended(_ suspended: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setSuspended(suspended) }
            return
        }

        self.isSuspended = suspended
    }

    func suppress(until date: Date) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.suppress(until: date) }
            return
        }

        self.suppressUntil = max(self.suppressUntil, date)
    }

    private func handle(_ event: NSEvent) {
        guard !self.isSuspended, Date() >= self.suppressUntil, AXIsProcessTrusted() else {
            return
        }

        for macro in MacroStore.shared.enabledOneShotMacros {
            guard let trigger = macro.trigger?.normalized, trigger.matches(event) else {
                continue
            }

            MacroRunCoordinator.shared.fire(macro)
            // Triggers are unique while enabled (enforced at save/enable time), so one match is
            // all there can be. Stopping here also keeps a single press from firing twice.
            break
        }
    }
}
