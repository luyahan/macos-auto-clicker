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

final class MacroStore: ObservableObject {
    static let shared = MacroStore()

    /// These are plain `@Published` properties rather than `@Default` ones. Defaults' own
    ///  documentation is explicit that `@Default` must not be used inside an `ObservableObject`:
    ///  writing through it updates `UserDefaults` but never fires `objectWillChange`, so the macro
    ///  list would keep rendering its stale selection. Persistence is therefore done by hand in
    ///  `persist()`.
    @Published private(set) var macros: [Macro] = []

    /// Mirrors the design, which only ever has one macro armed at a time.
    @Published private(set) var activeMacroID: UUID?

    var activeMacro: Macro? {
        guard let activeMacroID else {
            return nil
        }

        return self.macros.first { $0.id == activeMacroID }
    }

    var activeCount: Int {
        self.activeMacroID == nil ? 0 : 1
    }

    private init() {
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

        self.persist()
    }

    /// Writes the current state back to `UserDefaults`. Called after every mutation so that the
    ///  published properties stay the single source of truth for the views.
    private func persist() {
        Defaults[.macros] = self.macros
        Defaults[.activeMacroID] = self.activeMacroID
    }

    /// The design's exclusive-selection behaviour: arming one macro disarms every other.
    func activate(_ macro: Macro) {
        if self.activeMacroID == macro.id {
            self.activeMacroID = nil
        } else {
            self.activeMacroID = macro.id
        }

        self.persist()
    }

    func add() {
        var macro = Macro(name: "", caps: [KeyCap("CMD"), KeyCap("SHF"), KeyCap("S")], mode: .sequential)
        macro.name = String(format: NSLocalizedString("macro_untitled", comment: "Untitled macro"), self.macros.count + 1)

        self.macros.append(macro)
        self.activeMacroID = macro.id

        self.persist()
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

        if self.activeMacroID == macro.id {
            self.activeMacroID = nil
        }

        self.persist()
    }

    func macro(withID id: UUID) -> Macro? {
        self.macros.first { $0.id == id }
    }

    /// Used by the settings panel's "保存修改" button.
    func save(_ draft: Macro) {
        if self.macro(withID: draft.id) == nil {
            self.macros.append(draft)
        } else {
            self.update(draft)
        }
    }
}
