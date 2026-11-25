//
//  MacroRunner.swift
//  auto-clicker
//
//  Drives the macro the user has armed.
//
//  The keyboard shortcuts were registered by `MainView`, and the clicking was driven from
//  `FormState` — the settings tab's own configuration. Both predate the macro manager, so once the
//  window became `TriggerPilotView` nothing registered the shortcuts and a shortcut that did fire
//  would have replayed the settings tab's inputs rather than the armed macro.
//
//  This is the single place that connects the two: it registers the shortcuts for the lifetime of
//  the app and runs the armed macro through `AutoClickSimulator`.
//

import ApplicationServices
import Combine
import Foundation
import Defaults
import KeyboardShortcuts

final class MacroRunner: ObservableObject {
    static let shared = MacroRunner()

    /// Mirrors `AutoClickSimulator.isAutoClicking`.
    ///
    /// A macro finishes on its own once its repeat count is exhausted, and the simulator also stops
    ///  when the mouse moves and the user has asked for that. Both paths stop the simulator without
    ///  going through this class, so the flag is observed rather than set, otherwise the title bar
    ///  switch would stay on after the run had ended.
    @Published private(set) var isRunning = false

    /// Set when a start was asked for but there was nothing to run, so the UI can explain why
    ///  nothing happened instead of appearing to ignore the shortcut.
    @Published private(set) var lastRefusal: String?

    private var isRegistered = false
    private var observations = Set<AnyCancellable>()

    private init() {
        AutoClickSimulator.shared.$isAutoClicking
            .receive(on: RunLoop.main)
            .sink { [weak self] isAutoClicking in
                self?.isRunning = isAutoClicking
            }
            .store(in: &self.observations)
    }

    /// Registers the global start/stop shortcuts. Safe to call more than once — the app delegate
    ///  and the view both ask for it, and a second registration would stack a duplicate handler.
    func registerKeyboardShortcuts() {
        guard !self.isRegistered else {
            return
        }

        self.isRegistered = true

        KeyboardShortcuts.onKeyUp(for: .pressStartButton) { [weak self] in
            self?.start()
        }

        KeyboardShortcuts.onKeyUp(for: .pressStopButton) { [weak self] in
            self?.stop()
        }

        // One-shot macros listen for their own triggers for the whole app lifetime. Registration
        //  is idempotent, so this is the right place to install that single global monitor too.
        MacroTriggerService.shared.start()
    }

    /// Runs the armed macro.
    ///
    /// There is deliberately no fallback to the settings tab. Clicking the armed macro's row disarms
    ///  it, and the stats card then reports zero active macros — so starting a run at that point has
    ///  to do nothing and say so, rather than quietly clicking whatever the settings tab last held.
    func start() {
        // A start delay leaves the simulator idle while the countdown runs, so the timer has to be
        //  checked as well or a second press would stack another countdown on top of the first.
        guard !self.isRunning, !DelayTimer.shared.isCountingDown else {
            return
        }

        guard AXIsProcessTrusted() else {
            self.lastRefusal = NSLocalizedString("macro_error_no_permission", comment: "Accessibility permission missing")
            return
        }

        // One-shot macros are never started by the global shortcut: they fire from their own
        //  trigger. Starting one here would replay a macro the user never armed as a loop.
        guard let storedMacro = MacroStore.shared.activeMacro,
              storedMacro.activation == .repeating else {
            self.lastRefusal = NSLocalizedString("macro_error_none_armed", comment: "No macro armed")
            return
        }

        // Persisted values may be malformed or migrated from an older build. Clamp before use.
        let macro = storedMacro.validatedForExecution()

        // The macro's mode may not be able to deliver the combination it holds, e.g. a simultaneous
        //  chord with two keys in it. Refusing is better than running something the name does not
        //  describe.
        if let reason = macro.unsupportedReason {
            self.lastRefusal = NSLocalizedString(reason, comment: "Macro cannot be run as configured")
            return
        }

        if macro.executionScope == .application, macro.targetBundleIdentifier == nil {
            self.lastRefusal = NSLocalizedString("macro_error_target_missing", comment: "No target application selected")
            return
        }

        self.lastRefusal = nil
        self.run(using: macro.pressState,
                 name: macro.name,
                 targetBundleIdentifier: macro.executionScope == .application ? macro.targetBundleIdentifier : nil)
    }

    func stop() {
        // The delay timer must be stopped too, otherwise a running countdown would finish and fire
        //  its onFinish handler, restarting the run the user just asked to stop.
        DelayTimer.shared.stop()
        AutoClickSimulator.shared.stop()
        // Global Stop means everything, including in-flight one-shot runs. The triggers themselves
        //  stay armed: a switch, not a run, controls whether a macro listens.
        MacroRunCoordinator.shared.stopAll()
    }

    /// The one start path: an optional start delay, then the run.
    private func run(using state: FormState, name: String?, targetBundleIdentifier: String?) {
        let begin = {
            AutoClickSimulator.shared.start(using: state, targetBundleIdentifier: targetBundleIdentifier)

            // The simulator refuses invalid runs before any event is posted. Only announce a
            // macro that actually started, and honour the user's notification preference.
            guard let name,
                  AutoClickSimulator.shared.isAutoClicking,
                  Defaults[.notifyOnStart] else {
                return
            }

            NotificationService.scheduleNotification(
                title: String(format: NSLocalizedString("macro_started_title", comment: "Macro started"),
                              name),
                date: Date()
            )
        }

        if state.startDelay > 0 {
            DelayTimer.shared.start(seconds: state.startDelay, onFinish: begin)
        } else {
            begin()
        }
    }
}
