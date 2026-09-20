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

    // Said weird behaviour is still occuring in 12.2.1, thus having these defined in here instead of Published, I hate this though so much
    private var duration: Duration = .milliseconds
    private var interval: Int = DEFAULT_PRESS_INTERVAL
    private var amountOfPresses: Int = DEFAULT_REPEAT_AMOUNT
    private var inputs: [Input] = [Input()]

    /// The gap between the inputs of one press cycle. A macro's sequential interval lands here; the
    ///  legacy settings tab leaves it unset and keeps the fixed default.
    private var inputInterval: Int = PRESS_INPUT_INTERVAL

    /// How long a press is held before it is released, or `nil` to release immediately. Only a
    ///  long-press macro sets this.
    private var holdInterval: Int?

    /// Set while a macro is being run.
    ///
    /// A macro carries its own interval, repeat count and inputs, but those must not be written into
    ///  `Defaults[.autoClickerState]` — that is the user's configuration on the settings tab, and a
    ///  macro run would otherwise silently overwrite it. The override is held here for the duration
    ///  of the run instead and cleared on stop.
    private var overrideState: FormState?

    /// The configuration the current run reads from.
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

    /// Starts clicking.
    ///
    /// `state` lets a macro supply its own interval, repeat count and inputs for this run only; when
    ///  it is `nil` the user's settings tab configuration is used, which is what the menu bar and the
    ///  keyboard shortcut have always done.
    func start(using state: FormState? = nil) {
        self.overrideState = state

        self.isAutoClicking = true

        // Stop mouse start monitoring if it's running
        self.stopMouseStartMonitoring()

        if let startMenuItem = MenuBarService.startMenuItem {
            startMenuItem.isEnabled = false
        }

        if let stopMenuItem = MenuBarService.stopMenuItem {
            stopMenuItem.isEnabled = true
        }

        MenuBarService.changeImageColour(newColor: .systemBlue)

        self.activity = ProcessInfo.processInfo.beginActivity(.autoClicking)

        self.duration = self.activeState.pressIntervalDuration
        let intervalMode = self.activeState.intervalMode
        if intervalMode == .rangeInterval {
            let min = self.activeState.pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let max = self.activeState.pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: min...max)
        } else {
            self.interval = self.activeState.pressInterval
        }
        self.inputs = self.activeState.pressInputs.filter { !$0.readable.isEmpty }

        if self.inputs.isEmpty {
            self.inputs = [Input()]
        }

        self.amountOfPresses = self.activeState.pressAmount
        self.remainingInterations = self.activeState.repeatAmount

        self.inputInterval = max(0, self.activeState.pressInputInterval ?? PRESS_INPUT_INTERVAL)
        self.holdInterval = self.activeState.holdInterval
        self.finalClickAt = .init(timeInterval: self.duration.asTimeInterval(interval: self.interval * self.remainingInterations), since: .init())

        let timeInterval = self.duration.asTimeInterval(interval: self.interval)
        self.nextClickAt = .init(timeInterval: timeInterval, since: .init())
        self.timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                          target: self,
                                          selector: #selector(self.tick),
                                          userInfo: nil,
                                          repeats: true)

        if Defaults[.mouseStopOnMove] {
            self.initialMousePosition = nil
            self.mouseDeltaThreshold = CGFloat(Defaults[.mouseDeltaThreshold])
            startMouseMonitoring()
        }

        if Defaults[.notifyOnStart] {
            NotificationService.scheduleNotification(title: "Started", date: self.nextClickAt)
        }

        if Defaults[.notifyOnFinish] {
            NotificationService.scheduleNotification(title: "Finished", date: self.finalClickAt)
        }
    }

    func stop(triggeredByMouseMovement: Bool = false) {
        self.isAutoClicking = false

        // The override only lives for the duration of a run; leaving it set would make a later
        //  menu bar or shortcut start reuse the last macro's configuration.
        self.overrideState = nil

        if let monitorObject = self.monitorObject {
            NSEvent.removeMonitor(monitorObject)
            self.monitorObject = nil
        }

        if let startMenuItem = MenuBarService.startMenuItem {
            startMenuItem.isEnabled = true
        }

        if let stopMenuItem = MenuBarService.stopMenuItem {
            stopMenuItem.isEnabled = false
        }

        MenuBarService.resetImage()

        self.activity?.cancel()
        self.activity = nil

        // Force zero, as the user could stop the timer early
        self.remainingInterations = 0

        if let timer = self.timer {
            timer.invalidate()
        }

        if triggeredByMouseMovement {
            NotificationService.removePendingNotifications()

            if Defaults[.notifyOnFinish] {
                NotificationService.scheduleNotification(title: "Finished", date: Date())
            }
        } else {
            NotificationService.removePendingNotifications()
        }

        // Re-enable mouse start monitoring if it was enabled
        if Defaults[.mouseStartOnMove] && !self.isAutoClicking {
            self.startMouseStartMonitoring()
        }
    }

    func startMouseStartMonitoring() {
        // Stop any existing monitoring
        if let startMonitorObject = self.startMonitorObject {
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
        if let startMonitorObject = self.startMonitorObject {
            NSEvent.removeMonitor(startMonitorObject)
            self.startMonitorObject = nil
        }
    }

    @objc private func tick() {
        self.remainingInterations -= 1

        self.press()

        // Update interval if in range mode
        let intervalMode = self.activeState.intervalMode
        if intervalMode == .rangeInterval {
            let min = self.activeState.pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let max = self.activeState.pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: min...max)
        } else {
            self.interval = self.activeState.pressInterval
        }

        self.nextClickAt = .init(timeInterval: self.duration.asTimeInterval(interval: self.interval), since: .init())

        if self.remainingInterations <= 0 {
            self.stop()
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
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            if distance > mouseDeltaThreshold {
                self.stop(triggeredByMouseMovement: true)
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
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            if distance > mouseDeltaThreshold {
                // Stop monitoring and start the auto clicker
                self.stopMouseStartMonitoring()
                self.start()
            }
        } else {
            self.initialMousePosition = position
        }
    }

    private let mouseDownEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseDown,
        .leftMouseUp: .leftMouseDown,
        .rightMouseDown: .rightMouseDown,
        .rightMouseUp: .rightMouseDown,
        .otherMouseDown: .otherMouseDown,
        .otherMouseUp: .otherMouseDown
    ]

    private let mouseUpEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseUp,
        .leftMouseUp: .leftMouseUp,
        .rightMouseDown: .rightMouseUp,
        .rightMouseUp: .rightMouseUp,
        .otherMouseDown: .otherMouseUp,
        .otherMouseUp: .otherMouseUp
    ]

    private let mouseButtonEventMap: [NSEvent.EventType: CGMouseButton] = [
        .leftMouseDown: .left,
        .leftMouseUp: .left,
        .rightMouseDown: .right,
        .rightMouseUp: .right,
        .otherMouseDown: .center,
        .otherMouseUp: .center
    ]

    /// The modifier flags an event should carry.
    ///
    /// The flags are accumulated rather than assigned. Assigning would let each modifier overwrite
    ///  the previous one, so a Cmd+Shift chord would arrive as Shift alone — which is why a recorded
    ///  combination did not behave like the macro it came from.
    private func modifierFlags(for input: Input) -> CGEventFlags {
        var flags = CGEventFlags()

        if input.modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }

        if input.modifiers.contains(.control) {
            flags.insert(.maskControl)
        }

        if input.modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }

        if input.modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }

        // A modifier pressed as its own event, which is what a sequential macro produces for its
        //  modifier caps, also has to carry its flag or the target sees a bare key code.
        switch input.keyCode {
        case 55, 54: flags.insert(.maskCommand)
        case 56, 60: flags.insert(.maskShift)
        case 58, 61: flags.insert(.maskAlternate)
        case 59, 62: flags.insert(.maskControl)
        default: break
        }

        return flags
    }

    private func generateMouseClickEvents(source: CGEventSource?, input: Input) -> [CGEvent?] {
        let mouseX = self.mouseLocation.x
        let mouseY = NSScreen.screens[0].frame.height - mouseLocation.y

        let clickingAtPoint = CGPoint(x: mouseX, y: mouseY)

        let mouseDownType: CGEventType = mouseDownEventMap[input.type]!
        let mouseUpType: CGEventType = mouseUpEventMap[input.type]!
        let mouseButton: CGMouseButton = self.mouseButton(for: input)

        let mouseDown = CGEvent(mouseEventSource: source,
                                mouseType: mouseDownType,
                                mouseCursorPosition: clickingAtPoint,
                                mouseButton: mouseButton)

        let mouseUp = CGEvent(mouseEventSource: source,
                              mouseType: mouseUpType,
                              mouseCursorPosition: clickingAtPoint,
                              mouseButton: mouseButton)

        // A click can be modified too — Cmd+click, Shift+click — so the flags are set here as well
        //  rather than only on key events.
        let flags = self.modifierFlags(for: input)

        mouseDown?.flags = flags
        mouseUp?.flags = flags

        return [mouseDown, mouseUp]
    }

    /// The button number to put on the event.
    ///
    /// The map only knows left, right and centre, but `CGMouseButton` is a plain `UInt32`, so a
    ///  macro's side button can be forwarded as the number it actually is. The map is still what
    ///  decides left and right, which keeps the settings tab's own inputs behaving as before.
    private func mouseButton(for input: Input) -> CGMouseButton {
        let mapped: CGMouseButton = mouseButtonEventMap[input.type]!

        guard mapped == .center, input.keyCode > 2 else {
            return mapped
        }

        return CGMouseButton(rawValue: UInt32(input.keyCode)) ?? mapped
    }

    private func generateKeyPressEvents(source: CGEventSource?, input: Input) -> [CGEvent?] {
        let keyDown = CGEvent(keyboardEventSource: source,
                              virtualKey: CGKeyCode(input.keyCode),
                              keyDown: true)

        let keyUp = CGEvent(keyboardEventSource: source,
                            virtualKey: CGKeyCode(input.keyCode),
                            keyDown: false)

        let flags = self.modifierFlags(for: input)

        keyDown?.flags = flags
        keyUp?.flags = flags

        return [keyDown, keyUp]
    }

    private func press() {
        let source: CGEventSource? = CGEventSource(stateID: .hidSystemState)

        var completedPressesThisAction = 0

        while completedPressesThisAction < self.amountOfPresses {
            for (index, input) in self.inputs.enumerated() {
                let pressEvents = input.isMouseInput
                                    ? generateMouseClickEvents(source: source, input: input)
                                    : generateKeyPressEvents(source: source, input: input)

                // Both generators return the press followed by its release. A long press has to hold
                //  the key down instead, so only the press is posted here and the release is posted
                //  by `release(source:)` once the hold has elapsed.
                let holdsKeyDown = self.holdInterval != nil

                for (offset, event) in pressEvents.enumerated() where !(holdsKeyDown && offset > 0) {
                    event!.post(tap: .cghidEventTap)

                    LoggerService.simPress(input: input, location: event!.location)
                }

                // Space out multiple inputs within a single press cycle so each one lands. The gap
                //  is the macro's sequential interval when it has one, otherwise the fixed default.
                if index < self.inputs.count - 1 {
                    usleep(UInt32(self.inputInterval) * 1000)
                }
            }

            completedPressesThisAction += 1
        }

        // A long press is a chord that is held: the events above only went down, so the matching
        //  releases are posted once the hold has elapsed. Without this the target would see the key
        //  go down and never come up, which is a sticky modifier rather than a long press.
        if let holdInterval = self.holdInterval, holdInterval > 0 {
            usleep(UInt32(holdInterval) * 1000)
            self.release(source: source)
        }

        // One tick is one firing of the macro, so it counts once however many keys the combination
        //  holds.
        TriggerCounter.shared.record()
    }

    /// Posts the key-up / mouse-up half of a held press.
    private func release(source: CGEventSource?) {
        for input in self.inputs {
            let events = input.isMouseInput
                            ? generateMouseReleaseEvents(source: source, input: input)
                            : generateKeyReleaseEvents(source: source, input: input)

            for event in events {
                event!.post(tap: .cghidEventTap)
            }
        }
    }

    private func generateKeyReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent?] {
        let keyUp = CGEvent(keyboardEventSource: source,
                            virtualKey: CGKeyCode(input.keyCode),
                            keyDown: false)

        keyUp?.flags = self.modifierFlags(for: input)

        return [keyUp]
    }

    private func generateMouseReleaseEvents(source: CGEventSource?, input: Input) -> [CGEvent?] {
        let mouseY = NSScreen.screens[0].frame.height - self.mouseLocation.y
        let clickingAtPoint = CGPoint(x: self.mouseLocation.x, y: mouseY)

        let mouseUp = CGEvent(mouseEventSource: source,
                              mouseType: self.mouseUpEventMap[input.type]!,
                              mouseCursorPosition: clickingAtPoint,
                              mouseButton: self.mouseButton(for: input))

        mouseUp?.flags = self.modifierFlags(for: input)

        return [mouseUp]
    }
}
