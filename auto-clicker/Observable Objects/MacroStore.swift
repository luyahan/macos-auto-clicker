//
//  MacroStore.swift
//  auto-clicker
//
//  Observable owner of the macro list. Kept separate from `FormState` (which still backs the
//  auto-clicker simulator) so that adding the macro manager cannot invalidate an existing
//  user's stored form state.
//

import Defaults
import Foundation

/// The side effects `MacroStore` triggers when arm state changes: stopping in-flight runs and the
///  looping runner. Isolated behind a protocol so the store can be unit-tested without touching the
///  real `MacroRunCoordinator` / `MacroRunner` singletons (which own AppKit event monitors,
///  notifications and TCC checks).
protocol MacroStoreRuntime {
    func stopRun(macroID: UUID)
    func stopAllRuns()
    func stopLoopingRunner()
}

/// Production wiring: forwards to the real singletons.
struct LiveMacroStoreRuntime: MacroStoreRuntime {
    func stopRun(macroID: UUID) { MacroRunCoordinator.shared.stop(macroID: macroID) }
    func stopAllRuns() { MacroRunCoordinator.shared.stopAll() }
    func stopLoopingRunner() { MacroRunner.shared.stop() }
}

final class MacroStore: ObservableObject {
    static let shared = MacroStore()

    private let runtime: MacroStoreRuntime

    /// These are plain `@Published` properties rather than `@Default` ones. Defaults' own
    ///  documentation is explicit that `@Default` must not be used inside an `ObservableObject`:
    ///  writing through it updates `UserDefaults` but never fires `objectWillChange`, so the macro
    ///  list would keep rendering its stale selection. Persistence is therefore done by hand in
    ///  `persist()`.
    @Published private(set) var macros: [Macro] = []

    /// The single armed looping macro. One-shot macros do not use this: they carry their own
    ///  `isEnabled` flag, which is what lets several of them listen at once.
    @Published private(set) var activeMacroID: UUID?

    var activeMacro: Macro? {
        guard let activeMacroID else {
            return nil
        }

        return self.macros.first { $0.id == activeMacroID }
    }

    var repeatingMacros: [Macro] {
        self.macros.filter { $0.activation == .repeating }
    }

    var oneShotMacros: [Macro] {
        self.macros.filter { $0.activation == .oneShot }
    }

    /// What the global trigger monitor listens for. Read at event time, so editing this list needs
    ///  no monitor reinstall. Deliberately keeps this to cheap in-memory checks: the monitor sees
    ///  every key press made in other apps, and `triggerIssue` reads the shortcut settings.
    var enabledOneShotMacros: [Macro] {
        self.oneShotMacros.filter { $0.isEnabled && ($0.trigger?.isValid ?? false) }
    }

    /// The stats card counts every armed listener: one loop at most, plus any number of one-shots.
    var activeCount: Int {
        (self.activeMacroID == nil ? 0 : 1) + self.enabledOneShotMacros.count
    }

    /// Internal (not private) so unit tests can build an isolated instance with a stubbed runtime.
    ///  Production code keeps using the `shared` singleton.
    init(runtime: MacroStoreRuntime = LiveMacroStoreRuntime()) {
        self.runtime = runtime
        self.macros = Defaults[.macros]
        self.activeMacroID = Defaults[.activeMacroID]

        // Only a first run is seeded. Deciding from `macros.isEmpty` would resurrect the seed data
        //  every time the user deleted every macro on purpose, and deciding the initial activation
        //  from `activeMacroID == nil` would undo a deliberate disarm.
        if !Defaults[.macrosSeeded] {
            if self.macros.isEmpty {
                self.macros = Macro.seed

                // The design shows the first macro armed, so honour that on a fresh install.
                self.activeMacroID = self.macros.first?.id
            }

            // An existing install keeps whatever it already had stored, including "nothing armed".
            Defaults[.macrosSeeded] = true
        }

        self.reconcile()
        self.persist()
    }

    /// Repairs two states that a hand-edited preferences file (or a half-finished save) can hold:
    ///  a looping pointer aimed at a one-shot macro, and two enabled one-shots sharing a trigger.
    private func reconcile() {
        if let id = self.activeMacroID,
           self.macros.first(where: { $0.id == id })?.activation != .repeating {
            self.activeMacroID = nil
        }

        var seen: Set<MacroTrigger> = []

        for index in self.macros.indices {
            guard self.macros[index].activation == .oneShot, self.macros[index].isEnabled else {
                continue
            }

            self.macros[index].trigger = self.macros[index].trigger?.normalized

            guard let trigger = self.macros[index].trigger, trigger.isValid,
                  self.macros[index].triggerIssue == nil else {
                self.macros[index].isEnabled = false
                continue
            }

            if seen.contains(trigger) {
                self.macros[index].isEnabled = false
            } else {
                seen.insert(trigger)
            }
        }
    }

    /// Writes the current state back to `UserDefaults`. Called after every mutation so that the
    ///  published properties stay the single source of truth for the views.
    private func persist() {
        Defaults[.macros] = self.macros
        Defaults[.activeMacroID] = self.activeMacroID
    }

    /// The design's exclusive-selection behaviour, for looping macros only.
    func activate(_ macro: Macro) {
        guard macro.activation == .repeating else { return }

        if self.activeMacroID == macro.id {
            self.activeMacroID = nil
        } else {
            self.activeMacroID = macro.id
        }

        self.persist()
    }

    /// Independent arm state for one-shot macros. Enabling one does not disarm any other, except
    ///  when two of them would claim the same trigger — the later one wins and the earlier is
    ///  switched off, so a single press can never be ambiguous.
    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = self.macros.firstIndex(where: { $0.id == id }),
              self.macros[index].activation == .oneShot else {
            return
        }

        self.macros[index].isEnabled = enabled

        if enabled {
            self.resolveTriggerConflicts(keeping: id)
        } else {
            self.runtime.stopRun(macroID: id)
        }

        self.persist()
    }

    /// Another enabled one-shot macro already claiming this trigger. The settings panel uses this
    ///  to explain a refused save instead of silently disarming a macro behind the user's back.
    func conflictingMacro(for trigger: MacroTrigger?, excluding id: UUID) -> Macro? {
        guard let trigger = trigger?.normalized, trigger.isValid else { return nil }

        return self.macros.first {
            $0.id != id
                && $0.activation == .oneShot
                && $0.isEnabled
                && $0.trigger?.normalized == trigger
        }
    }

    private func resolveTriggerConflicts(keeping id: UUID) {
        guard let kept = self.macros.first(where: { $0.id == id }),
              kept.activation == .oneShot, kept.isEnabled,
              let trigger = kept.trigger?.normalized else {
            return
        }

        for index in self.macros.indices where self.macros[index].id != id {
            guard self.macros[index].activation == .oneShot,
                  self.macros[index].isEnabled,
                  self.macros[index].trigger?.normalized == trigger else {
                continue
            }

            self.macros[index].isEnabled = false
            self.runtime.stopRun(macroID: self.macros[index].id)
        }
    }

    func add(activation: MacroActivation = .repeating) {
        let number = self.macros.count + 1
        var macro: Macro

        switch activation {
        case .repeating:
            macro = Macro(name: "", caps: [KeyCap("CMD"), KeyCap("SHF"), KeyCap("S")], mode: .sequential)
            macro.name = String(format: NSLocalizedString("macro_untitled", comment: "Untitled macro"), number)
            self.activeMacroID = macro.id

        case .oneShot:
            macro = Macro(name: String(format: NSLocalizedString("macro_untitled_one_shot",
                                                                 comment: "Untitled one-shot macro"), number),
                          caps: [KeyCap(mouseButton: 0)],
                          mode: .simultaneous,
                          activation: .oneShot,
                          trigger: MacroTrigger(mouseButton: self.nextAvailableMouseButton()),
                          isEnabled: false)
        }

        self.macros.append(macro)
        self.persist()
    }

    /// Side buttons are the natural one-shot triggers, so each new macro starts on a free one
    ///  rather than colliding with the previous macro out of the box.
    private func nextAvailableMouseButton() -> Int {
        let taken = Set(self.oneShotMacros.compactMap { $0.trigger?.mouseButton })

        for button in 3...15 where !taken.contains(button) {
            return button
        }

        return 3
    }

    func update(_ macro: Macro) {
        guard let index = self.macros.firstIndex(where: { $0.id == macro.id }) else {
            return
        }

        self.macros[index] = macro

        self.persist()
    }

    func delete(_ macro: Macro) {
        self.macros.removeAll { $0.id == macro.id }
        self.runtime.stopRun(macroID: macro.id)

        if self.activeMacroID == macro.id {
            self.activeMacroID = nil
        }

        self.persist()
    }

    func macro(withID id: UUID) -> Macro? {
        self.macros.first { $0.id == id }
    }

    /// Used by the settings panel's "保存修改" button.
    ///
    /// Converting a macro between the two groups has to undo the arm state of the old group,
    ///  otherwise a disabled one-shot would keep its trigger or an armed loop would keep pointing
    ///  at a macro that no longer loops.
    func save(_ draft: Macro) {
        var macro = draft

        if macro.activation == .oneShot {
            macro.repeatCount = 1
            macro.delayEnabled = false
            macro.delaySeconds = 0
            macro.trigger = macro.trigger?.normalized
        } else {
            macro.isEnabled = false
        }

        guard let index = self.macros.firstIndex(where: { $0.id == macro.id }) else {
            self.macros.append(macro)
            self.persist()
            return
        }

        let previous = self.macros[index]
        self.macros[index] = macro

        if previous.activation != macro.activation {
            if macro.activation == .oneShot, self.activeMacroID == macro.id {
                self.activeMacroID = nil
                self.runtime.stopLoopingRunner()
            }

            self.runtime.stopRun(macroID: macro.id)
        }

        if !macro.isEnabled || macro.activation == .repeating {
            self.runtime.stopRun(macroID: macro.id)
        }

        if macro.activation == .oneShot, macro.isEnabled {
            self.resolveTriggerConflicts(keeping: macro.id)
        }

        self.persist()
    }
}
