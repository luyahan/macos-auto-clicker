//
//  MacroStoreTests.swift
//  auto-clickerTests
//
//  Unit tests for the macro store's arm-state rules. These run against an isolated `MacroStore`
//  instance with a stubbed runtime, so no real event monitor, notification or TCC check is touched.
//

import XCTest
import Defaults
@testable import AutoClicker

/// Records the side-effect calls the store makes, instead of driving the real coordinator/runner.
final class StubMacroStoreRuntime: MacroStoreRuntime {
    var stoppedRunIDs: [UUID] = []
    var stopAllRunsCallCount = 0
    var stopLoopingRunnerCallCount = 0

    func stopRun(macroID: UUID) { self.stoppedRunIDs.append(macroID) }
    func stopAllRuns() { self.stopAllRunsCallCount += 1 }
    func stopLoopingRunner() { self.stopLoopingRunnerCallCount += 1 }
}

final class MacroStoreTests: XCTestCase {
    private var runtime: StubMacroStoreRuntime!
    private var store: MacroStore!

    /// The `UserDefaults` keys `MacroStore` reads and writes. `Defaults` binds to
    ///  `UserDefaults.standard` with no injection point, so tests snapshot and restore these keys
    ///  to avoid clobbering the developer's real configuration.
    private var savedValues: [String: Any?] = [:]
    private let defaultsKeys = ["macro_list", "macro_active_id", "macro_list_seeded"]

    override func setUp() {
        super.setUp()

        // Snapshot the real values, then start from a clean, already-seeded slate.
        for key in self.defaultsKeys {
            self.savedValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(true, forKey: "macro_list_seeded")

        self.runtime = StubMacroStoreRuntime()
        self.store = MacroStore(runtime: self.runtime)
    }

    override func tearDown() {
        // Restore whatever the developer had before the test ran.
        for key in self.defaultsKeys {
            if let value = self.savedValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        self.savedValues = [:]
        self.store = nil
        self.runtime = nil

        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRepeatingMacro() -> Macro {
        Macro(name: "loop", caps: [KeyCap("S", isAccent: true)], mode: .sequential)
    }

    private func makeOneShotMacro(button: Int, enabled: Bool = false) -> Macro {
        Macro(name: "one-shot \(button)",
              caps: [KeyCap(mouseButton: 0)],
              mode: .simultaneous,
              activation: .oneShot,
              trigger: MacroTrigger(mouseButton: button),
              isEnabled: enabled)
    }

    @discardableResult
    private func addOneShot(_ macro: Macro) -> Macro {
        self.store.save(macro)
        return macro
    }

    // MARK: - activate (looping macros are mutually exclusive)

    func testActivatingRepeatingMacroDisarmsPrevious() {
        let first = self.makeRepeatingMacro()
        let second = self.makeRepeatingMacro()
        self.store.save(first)
        self.store.save(second)

        self.store.activate(first)
        XCTAssertEqual(self.store.activeMacroID, first.id)

        self.store.activate(second)
        XCTAssertEqual(self.store.activeMacroID, second.id)
        XCTAssertEqual(self.store.activeCount, 1)
    }

    func testActivatingSameRepeatingMacroTwiceDisarms() {
        let macro = self.makeRepeatingMacro()
        self.store.save(macro)

        self.store.activate(macro)
        XCTAssertEqual(self.store.activeMacroID, macro.id)

        self.store.activate(macro)
        XCTAssertNil(self.store.activeMacroID)
        XCTAssertEqual(self.store.activeCount, 0)
    }

    func testActivateIgnoresOneShotMacro() {
        let oneShot = self.addOneShot(self.makeOneShotMacro(button: 3))

        self.store.activate(oneShot)

        XCTAssertNil(self.store.activeMacroID, "A one-shot macro must never become the armed loop")
    }

    // MARK: - setEnabled (one-shot macros are independent)

    func testEnablingOneShotDoesNotDisarmOtherOneShots() {
        let first = self.addOneShot(self.makeOneShotMacro(button: 3))
        let second = self.addOneShot(self.makeOneShotMacro(button: 4))

        self.store.setEnabled(true, for: first.id)
        self.store.setEnabled(true, for: second.id)

        XCTAssertEqual(self.store.enabledOneShotMacros.count, 2)
        XCTAssertEqual(self.store.activeCount, 2)
    }

    func testEnablingSameTriggerDisarmsTheOtherOneShot() {
        let first = self.addOneShot(self.makeOneShotMacro(button: 3))
        let second = self.addOneShot(self.makeOneShotMacro(button: 3))

        self.store.setEnabled(true, for: first.id)
        self.store.setEnabled(true, for: second.id)

        let enabled = self.store.enabledOneShotMacros
        XCTAssertEqual(enabled.count, 1, "Two macros must not share one trigger")
        XCTAssertEqual(enabled.first?.id, second.id, "The most recently enabled macro wins")
        XCTAssertTrue(self.runtime.stoppedRunIDs.contains(first.id),
                      "The disarmed macro's in-flight run must be stopped")
    }

    func testEnablingOneShotDoesNotDisarmLoopingMacro() {
        let loop = self.makeRepeatingMacro()
        self.store.save(loop)
        self.store.activate(loop)

        let oneShot = self.addOneShot(self.makeOneShotMacro(button: 3))
        self.store.setEnabled(true, for: oneShot.id)

        XCTAssertEqual(self.store.activeMacroID, loop.id)
        XCTAssertEqual(self.store.activeCount, 2)
    }

    func testDisablingOneShotStopsItsRun() {
        let oneShot = self.addOneShot(self.makeOneShotMacro(button: 3))
        self.store.setEnabled(true, for: oneShot.id)
        self.store.setEnabled(false, for: oneShot.id)

        XCTAssertTrue(self.runtime.stoppedRunIDs.contains(oneShot.id))
        XCTAssertEqual(self.store.enabledOneShotMacros.count, 0)
    }

    func testOneShotWithoutTriggerCannotBeEnabledAsListener() {
        var oneShot = self.makeOneShotMacro(button: 3)
        oneShot.trigger = nil
        oneShot.isEnabled = true
        self.store.save(oneShot)

        // The enabled list filters out trigger-less macros even if `isEnabled` was persisted true.
        XCTAssertEqual(self.store.enabledOneShotMacros.count, 0)
    }

    // MARK: - conflictingMacro

    func testConflictingMacroFindsOtherEnabledMacroWithSameTrigger() {
        let first = self.addOneShot(self.makeOneShotMacro(button: 5, enabled: true))

        let conflict = self.store.conflictingMacro(for: MacroTrigger(mouseButton: 5),
                                                   excluding: UUID())
        XCTAssertEqual(conflict?.id, first.id)

        let none = self.store.conflictingMacro(for: MacroTrigger(mouseButton: 9),
                                               excluding: UUID())
        XCTAssertNil(none)
    }

    func testConflictingMacroIgnoresItselfAndDisabledMacros() {
        let first = self.addOneShot(self.makeOneShotMacro(button: 5, enabled: true))
        let disabled = self.addOneShot(self.makeOneShotMacro(button: 5, enabled: false))

        XCTAssertNil(self.store.conflictingMacro(for: MacroTrigger(mouseButton: 5),
                                                 excluding: first.id),
                     "A macro never conflicts with itself")
        XCTAssertNotNil(disabled)
    }

    // MARK: - add

    func testAddRepeatingMacroArmsIt() {
        self.store.add(activation: .repeating)

        XCTAssertEqual(self.store.repeatingMacros.count, 1)
        XCTAssertEqual(self.store.activeMacroID, self.store.repeatingMacros.first?.id)
    }

    func testAddOneShotMacroPicksUnusedSideButton() {
        self.addOneShot(self.makeOneShotMacro(button: 3))

        self.store.add(activation: .oneShot)

        let added = self.store.oneShotMacros.last
        XCTAssertEqual(added?.trigger?.mouseButton, 4, "New one-shot should take the next free button")
        XCTAssertEqual(added?.activation, .oneShot)
        XCTAssertFalse(added?.isEnabled ?? true, "A new one-shot starts disarmed")
    }

    // MARK: - save (conversion between groups)

    func testSavingOneShotForcesSingleRoundAndNoDelay() {
        var oneShot = self.makeOneShotMacro(button: 3)
        oneShot.repeatCount = 99
        oneShot.delayEnabled = true
        oneShot.delaySeconds = 5

        self.store.save(oneShot)

        let saved = self.store.macro(withID: oneShot.id)
        XCTAssertEqual(saved?.repeatCount, 1)
        XCTAssertFalse(saved?.delayEnabled ?? true)
        XCTAssertEqual(saved?.delaySeconds, 0)
    }

    func testConvertingRepeatingToOneShotClearsActivePointer() {
        let loop = self.makeRepeatingMacro()
        self.store.save(loop)
        self.store.activate(loop)

        var converted = loop
        converted.activation = .oneShot
        converted.trigger = MacroTrigger(mouseButton: 3)
        self.store.save(converted)

        XCTAssertNil(self.store.activeMacroID, "An armed loop converted to one-shot must disarm")
        XCTAssertEqual(self.runtime.stopLoopingRunnerCallCount, 1)
    }

    func testConvertingOneShotToRepeatingClearsEnabledFlag() {
        let oneShot = self.addOneShot(self.makeOneShotMacro(button: 3, enabled: true))

        var converted = oneShot
        converted.activation = .repeating
        self.store.save(converted)

        XCTAssertFalse(self.store.macro(withID: oneShot.id)?.isEnabled ?? true)
        XCTAssertEqual(self.store.enabledOneShotMacros.count, 0)
    }

    // MARK: - delete

    func testDeleteClearsActivePointerAndStopsRun() {
        let loop = self.makeRepeatingMacro()
        self.store.save(loop)
        self.store.activate(loop)

        self.store.delete(loop)

        XCTAssertNil(self.store.activeMacroID)
        XCTAssertTrue(self.runtime.stoppedRunIDs.contains(loop.id))
        XCTAssertEqual(self.store.repeatingMacros.count, 0)
    }

    // MARK: - reconcile (repairs hand-edited preferences)

    func testReconcileDisarmsDuplicateTriggersOnLaunch() {
        // Simulate two enabled one-shots with the same trigger already persisted.
        self.addOneShot(self.makeOneShotMacro(button: 7, enabled: true))
        self.addOneShot(self.makeOneShotMacro(button: 7, enabled: true))
        XCTAssertEqual(self.store.enabledOneShotMacros.count, 2, "Precondition: duplicates exist")

        // A fresh store instance re-reads the same defaults and must reconcile the conflict.
        let reconciled = MacroStore(runtime: StubMacroStoreRuntime())
        XCTAssertEqual(reconciled.enabledOneShotMacros.count, 1,
                       "On launch only one macro may hold a given trigger")
    }

    func testReconcileClearsActivePointerAimedAtOneShot() {
        let oneShot = self.addOneShot(self.makeOneShotMacro(button: 3))
        // Force the looping pointer at a one-shot macro, as a hand-edited plist could. Written
        // through `Defaults` itself so the value uses the exact serialization the store reads.
        Defaults[.activeMacroID] = oneShot.id

        let reconciled = MacroStore(runtime: StubMacroStoreRuntime())
        XCTAssertNil(reconciled.activeMacroID)
    }
}
