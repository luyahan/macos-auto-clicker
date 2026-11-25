//
//  AutoClickSimulator.swift
//  auto-clicker
//
//  Created by Ben Tindall on 12/05/2021.
//

import Foundation
import Combine
import SwiftUI
import Defaults
import UserNotifications

final class AutoClickSimulator: ObservableObject {
    static var shared: AutoClickSimulator = .init()
    private init() {}

    @Published var isAutoClicking = false
    @Published var remainingInterations: Int = 0
    @Published var nextClickAt: Date = .init()
    @Published var finalClickAt: Date = .init()

    private var duration: Duration = .milliseconds
    private var interval: Int = DEFAULT_PRESS_INTERVAL
    private var amountOfPresses: Int = DEFAULT_REPEAT_AMOUNT
    private var inputs: [Input] = [Input()]
    private var inputInterval: Int = PRESS_INPUT_INTERVAL
    private var holdInterval: Int?

    /// Configuration for this run only; cleared on stop.
    private var overrideState: FormState?
    private var targetBundleIdentifier: String?

    private var activeState: FormState {
        self.overrideState ?? Defaults[.autoClickerState]
    }

    private var timer: Timer?
    private var mouseLocation: NSPoint { NSEvent.mouseLocation }
    private var activity: Cancellable?

    private var monitorObject: Any?
    private var startMonitorObject: Any?
    private var initialMousePosition: NSPoint?
    private var mouseDeltaThreshold: CGFloat = 0.0

    // MARK: - Cancellable execution

    /// Event creation and posting never run on the main thread.
    private let eventQueue = DispatchQueue(label: "com.othyn.auto-clicker.events",
                                           qos: .userInitiated)

    /// Guarded by `runCondition`. Each in-flight round captures a token; stop invalidates it.
    private var runCondition = NSCondition()
    private var _runToken: UInt64 = 0

    private var currentRunToken: UInt64 {
        self.runCondition.lock()
        defer { self.runCondition.unlock() }
        return self._runToken
    }

    private func invalidateRun() {
        self.runCondition.lock()
        self._runToken &+= 1
        self.runCondition.broadcast()
        self.runCondition.unlock()
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        self.runCondition.lock()
        defer { self.runCondition.unlock() }
        return self._runToken == token
    }

    /// Sleeps on the event queue but wakes immediately when the run is stopped.
    @discardableResult
    private func cancellableSleep(milliseconds: Int, token: UInt64) -> Bool {
        guard milliseconds > 0 else { return self.isCurrent(token) }
        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1_000)

        self.runCondition.lock()
        defer { self.runCondition.unlock() }

        while self._runToken == token && Date() < deadline {
            self.runCondition.wait(until: deadline)
        }
        return self._runToken == token
    }

    /// Notifications belong to one run so a stopped run cannot cancel another run's notification.
    private var runNotificationID: String?

    // MARK: - Start / stop

    /// Starts clicking. Both macro and settings-tab configurations are validated first: no path
    /// may turn an empty input list into a silent default left click.
    func start(using state: FormState? = nil, targetBundleIdentifier: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.start(using: state, targetBundleIdentifier: targetBundleIdentifier)
            }
            return
        }

        guard !self.isAutoClicking, AXIsProcessTrusted() else { return }

        let safeState = (state ?? Defaults[.autoClickerState]).validatedForExecution()
        let safeInputs = safeState.pressInputs.filter { $0.isValidForExecution }
        guard !safeInputs.isEmpty else { return }

        self.overrideState = state == nil ? nil : safeState
        self.targetBundleIdentifier = targetBundleIdentifier
        self.isAutoClicking = true
        self.stopMouseStartMonitoring()

        if let startMenuItem = MenuBarService.startMenuItem { startMenuItem.isEnabled = false }
        if let stopMenuItem = MenuBarService.stopMenuItem { stopMenuItem.isEnabled = true }
        MenuBarService.changeImageColour(newColor: .systemBlue)
        self.activity = ProcessInfo.processInfo.beginActivity(.autoClicking)

        self.duration = safeState.pressIntervalDuration
        if safeState.intervalMode == .rangeInterval {
            let lower = safeState.pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let upper = safeState.pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: lower...upper)
        } else {
            self.interval = safeState.pressInterval
        }

        self.inputs = safeInputs
        self.amountOfPresses = safeState.pressAmount
        self.remainingInterations = safeState.repeatAmount
        self.inputInterval = safeState.pressInputInterval ?? PRESS_INPUT_INTERVAL
        self.holdInterval = safeState.holdInterval

        // Saturating arithmetic so a corrupted value cannot trap on overflow.
        let (product, overflow) = self.interval.multipliedReportingOverflow(
            by: max(0, self.remainingInterations - 1)
        )
        self.finalClickAt = .init(
            timeInterval: self.duration.asTimeInterval(interval: overflow ? Int.max : product),
            since: .init()
        )

        let timeInterval = self.duration.asTimeInterval(interval: self.interval)
        self.nextClickAt = .init(timeInterval: timeInterval, since: .init())
        self.timer = Timer.scheduledTimer(timeInterval: max(0.001, timeInterval),
                                          target: self,
                                          selector: #selector(self.tick),
                                          userInfo: nil,
                                          repeats: true)

        if Defaults[.mouseStopOnMove] {
            self.initialMousePosition = nil
            self.mouseDeltaThreshold = CGFloat(Defaults[.mouseDeltaThreshold])
            self.startMouseMonitoring()
        }

        let notificationID = UUID().uuidString
        self.runNotificationID = notificationID
        if Defaults[.notifyOnStart] {
            NotificationService.scheduleNotification(title: "Started",
                                                     date: Date(),
                                                     identifier: notificationID)
        }

        // Deliberately last: a one-round macro completes inside this call.
        self.performRound()
    }

    func stop(triggeredByMouseMovement: Bool = false) {
        let reason: StopReason = triggeredByMouseMovement ? .mouseMovement : .manual
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop(reason: reason) }
            return
        }
        self.stop(reason: reason)
    }

    enum StopReason {
        case manual, mouseMovement, completed, targetMismatch, permissionLost
    }

    private func stop(reason: StopReason) {
        // Wake any sleeping round and make in-flight blocks observe a stale token.
        self.invalidateRun()

        self.isAutoClicking = false
        self.overrideState = nil
        self.targetBundleIdentifier = nil

        if let monitorObject {
            NSEvent.removeMonitor(monitorObject)
            self.monitorObject = nil
        }
        if let startMenuItem = MenuBarService.startMenuItem { startMenuItem.isEnabled = true }
        if let stopMenuItem = MenuBarService.stopMenuItem { stopMenuItem.isEnabled = false }
        MenuBarService.resetImage()

        self.activity?.cancel()
        self.activity = nil
        self.remainingInterations = 0

        if let timer {
            timer.invalidate()
            self.timer = nil
        }

        if let notificationID = self.runNotificationID {
            NotificationService.removePendingNotifications(identifiers: [notificationID])
            self.runNotificationID = nil

            // Only a genuine end of work announces completion.
            if reason == .completed || reason == .mouseMovement,
               Defaults[.notifyOnFinish] {
                NotificationService.scheduleNotification(title: "Finished",
                                                         date: Date(),
                                                         identifier: notificationID)
            }
        }

        if Defaults[.mouseStartOnMove] && !self.isAutoClicking {
            self.startMouseStartMonitoring()
        }
    }

    // MARK: - Monitoring

    func startMouseStartMonitoring() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.startMouseStartMonitoring() }
            return
        }
        if let startMonitorObject {
            NSEvent.removeMonitor(startMonitorObject)
            self.startMonitorObject = nil
        }
        self.initialMousePosition = nil
        self.mouseDeltaThreshold = CGFloat(Defaults[.mouseDeltaThreshold])
        self.startMonitorObject = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.mouseMovedForStart(event)
        }
    }

    func stopMouseStartMonitoring() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stopMouseStartMonitoring() }
            return
        }
        if let startMonitorObject {
            NSEvent.removeMonitor(startMonitorObject)
            self.startMonitorObject = nil
        }
    }

    private func startMouseMonitoring() {
        self.monitorObject = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.mouseMoved(event)
        }
    }

    private func mouseMoved(_ event: NSEvent) {
        let position = event.locationInWindow
        if let initialPosition = self.initialMousePosition {
            let deltaX = position.x - initialPosition.x
            let deltaY = position.y - initialPosition.y
            if sqrt(deltaX * deltaX + deltaY * deltaY) > self.mouseDeltaThreshold {
                DispatchQueue.main.async { self.stop(reason: .mouseMovement) }
            }
        } else {
            self.initialMousePosition = position
        }
    }

    private func mouseMovedForStart(_ event: NSEvent) {
        let position = event.locationInWindow
        if let initialPosition = self.initialMousePosition {
            let deltaX = position.x - initialPosition.x
            let deltaY = position.y - initialPosition.y
            if sqrt(deltaX * deltaX + deltaY * deltaY) > self.mouseDeltaThreshold {
                DispatchQueue.main.async {
                    self.stopMouseStartMonitoring()
                    self.start()
                }
            }
        } else {
            self.initialMousePosition = position
        }
    }

    // MARK: - Round scheduling

    @objc private func tick() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.tick() }
            return
        }
        self.performRound()
    }

    private func performRound() {
        guard self.isAutoClicking else { return }

        guard AXIsProcessTrusted() else {
            self.stop(reason: .permissionLost)
            return
        }

        guard self.targetMatches(self.targetBundleIdentifier) else {
            // Do not leave the UI claiming a run is active while every round is silently skipped.
            self.stop(reason: .targetMismatch)
            return
        }

        self.remainingInterations -= 1
        TriggerCounter.shared.record()

        let state = self.activeState
        if state.intervalMode == .rangeInterval {
            let lower = state.pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let upper = state.pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: lower...upper)
        } else {
            self.interval = state.pressInterval
        }

        self.nextClickAt = .init(
            timeInterval: self.duration.asTimeInterval(interval: self.interval),
            since: .init()
        )

        let token = self.currentRunToken
        let inputs = self.inputs
        let amount = self.amountOfPresses
        let inputInterval = self.inputInterval
        let holdInterval = self.holdInterval
        let target = self.targetBundleIdentifier

        self.eventQueue.async { [weak self] in
            guard let self else { return }

            self.executeRound(token: token,
                               target: target,
                               inputs: inputs,
                               amount: amount,
                               inputInterval: inputInterval,
                               holdInterval: holdInterval)

            DispatchQueue.main.async {
                guard self.isCurrent(token) else { return }
                if self.remainingInterations <= 0 {
                    self.stop(reason: .completed)
                }
            }
        }
    }

    /// Posts one whole round on the event queue. The target and run token are checked before
    /// every event. Held inputs are released even when the round is cancelled mid-hold.
    private func executeRound(token: UInt64,
                              target: String?,
                              inputs: [Input],
                              amount: Int,
                              inputInterval: Int,
                              holdInterval: Int?) {
        let source = CGEventSource(stateID: .hidSystemState)
        let holdsKeyDown = holdInterval != nil
        var heldInputs: [Input] = []
        var cancelled = false

        for _ in 0..<max(0, amount) {
            for (index, input) in inputs.enumerated() {
                guard self.canPost(token: token, target: target) else {
                    cancelled = true
                    break
                }

                let events = input.isMouseInput
                    ? self.generateMouseClickEvents(source: source, input: input)
                    : self.generateKeyPressEvents(source: source, input: input)

                if holdsKeyDown {
                    if let down = events.first {
                        down.post(tap: .cghidEventTap)
                        heldInputs.append(input)
                    }
                } else {
                    for event in events {
                        guard self.canPost(token: token, target: target) else {
                            cancelled = true
                            break
                        }
                        event.post(tap: .cghidEventTap)
                    }
                }

                if cancelled { break }

                if index < inputs.count - 1,
                   !self.cancellableSleep(milliseconds: inputInterval, token: token) {
                    cancelled = true
                    break
                }
            }
            if cancelled { break }
        }

        if let holdInterval, holdInterval > 0,
           !self.cancellableSleep(milliseconds: holdInterval, token: token) {
            cancelled = true
        }

        // Always release held inputs, including after cancellation.
        for input in heldInputs {
            let releases = input.isMouseInput
                ? self.generateMouseReleaseEvents(source: source, input: input)
                : self.generateKeyReleaseEvents(source: source, input: input)
            for event in releases {
                event.post(tap: .cghidEventTap)
            }
        }

        if cancelled {
            DispatchQueue.main.async { self.stop(reason: .targetMismatch) }
        }
    }

    private func canPost(token: UInt64, target: String?) -> Bool {
        guard self.isCurrent(token), AXIsProcessTrusted() else { return false }
        return self.targetMatches(target)
    }

    /// `NSWorkspace` is read on the main thread; the event queue calls this before every event.
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

    // MARK: - Event creation

    private let mouseDownEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseDown, .leftMouseUp: .leftMouseDown,
        .rightMouseDown: .rightMouseDown, .rightMouseUp: .rightMouseDown,
        .otherMouseDown: .otherMouseDown, .otherMouseUp: .otherMouseDown
    ]

    private let mouseUpEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseUp, .leftMouseUp: .leftMouseUp,
        .rightMouseDown: .rightMouseUp, .rightMouseUp: .rightMouseUp,
        .otherMouseDown: .otherMouseUp, .otherMouseUp: .otherMouseUp
    ]

    private let mouseButtonEventMap: [NSEvent.EventType: CGMouseButton] = [
        .leftMouseDown: .left, .leftMouseUp: .left,
        .rightMouseDown: .right, .rightMouseUp: .right,
        .otherMouseDown: .center, .otherMouseUp: .center
    ]

    private func modifierFlags(for input: Input) -> CGEventFlags {
        var flags = CGEventFlags()

        if input.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if input.modifiers.contains(.control) { flags.insert(.maskControl) }
        if input.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if input.modifiers.contains(.shift) { flags.insert(.maskShift) }

        switch input.keyCode {
        case 55, 54: flags.insert(.maskCommand)
        case 56, 60: flags.insert(.maskShift)
        case 58, 61: flags.insert(.maskAlternate)
        case 59, 62: flags.insert(.maskControl)
        default: break
        }

        return flags
    }

    private func generateMouseClickEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let downType = mouseDownEventMap[input.type],
              let upType = mouseUpEventMap[input.type] else {
            return []
        }

        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: self.mouseLocation.x,
                            y: screenHeight - self.mouseLocation.y)
        let button = self.mouseButton(for: input)

        let mouseDown = CGEvent(mouseEventSource: source,
                                mouseType: downType,
                                mouseCursorPosition: point,
                                mouseButton: button)
        let mouseUp = CGEvent(mouseEventSource: source,
                              mouseType: upType,
                              mouseCursorPosition: point,
                              mouseButton: button)

        let flags = self.modifierFlags(for: input)
        mouseDown?.flags = flags
        mouseUp?.flags = flags

        return [mouseDown, mouseUp].compactMap { $0 }
    }

    /// Side buttons travel as `otherMouse` events with their real button number in `keyCode`.
    private func mouseButton(for input: Input) -> CGMouseButton {
        guard let mapped = mouseButtonEventMap[input.type] else { return .left }

        guard mapped == .center, input.keyCode > 2 else { return mapped }
        return CGMouseButton(rawValue: UInt32(input.keyCode)) ?? mapped
    }

    private func generateKeyPressEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        let keyDown = CGEvent(keyboardEventSource: source,
                              virtualKey: CGKeyCode(input.keyCode),
                              keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source,
                            virtualKey: CGKeyCode(input.keyCode),
                            keyDown: false)

        let flags = self.modifierFlags(for: input)
        keyDown?.flags = flags
        keyUp?.flags = flags

        return [keyDown, keyUp].compactMap { $0 }
    }

    private func generateKeyReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(input.keyCode),
                                  keyDown: false) else {
            return []
        }
        keyUp.flags = self.modifierFlags(for: input)
        return [keyUp]
    }

    private func generateMouseReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent] {
        guard let upType = mouseUpEventMap[input.type],
              let mouseUp = CGEvent(mouseEventSource: source,
                                    mouseType: upType,
                                    mouseCursorPosition: CGPoint(
                                        x: self.mouseLocation.x,
                                        y: (NSScreen.main?.frame.height
                                            ?? NSScreen.screens.first?.frame.height
                                            ?? 0) - self.mouseLocation.y
                                    ),
                                    mouseButton: self.mouseButton(for: input)) else {
            return []
        }
        mouseUp.flags = self.modifierFlags(for: input)
        return [mouseUp]
    }
}
