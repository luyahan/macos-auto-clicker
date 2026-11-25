//
//  LoggerService.swift
//  auto-clicker
//
//  Created by Ben Tindall on 12/04/2022.
//

import SwiftUI

final class LoggerService {
    private static func log(file: String, function: String, _ lines: [String]) {
        #if DEBUG
        NSLog(">~  Who: \(file) ~ \(function)")

        for line in lines {
            NSLog(">~ What: \(line)")
        }
        #endif
    }

    static func permissionState(enabled: Bool, callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "App permissions \(enabled ? "" : "not ")granted"
        ])
    }

    static func notificationState(enabled: Bool, callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "Notification permissions \(enabled ? "" : "not ")granted"
        ])
    }

    static func logNotification(title: String, body: String? = nil, date: Date, interval: TimeInterval, callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "Title: \(title)",
            "Body: \(String(describing: body))",
            "Date: \(date)",
            "Interval: \(interval)",
            "Current Date: \(Date())"
        ])
    }

    static func permissionTrustedState(callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "Is trusted: \(AXIsProcessTrusted())"
        ])
    }

    static func numberValidator<CallingView: View>(view: CallingView, oldNumber: Int, oldString: String, newString: String, newIntString: String, callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "View: \(String(describing: type(of: view)))",
            "Old Number: \(oldNumber) | Old Value: \(oldString)",
            "New Number: \(newIntString) | New Value: \(newString)"
        ])
    }

    static func pressInputEvent(event: NSEvent, callingFile: String = #fileID, callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "Pressed: \(event.inputString)"
        ])
    }

    /// Input events contain what the user typed and where they clicked. Debug logging of those
    /// values is opt-in even in Debug builds so a development session cannot silently record them.
    private static var verboseInputLogging: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "debug_verbose_input_logging")
        #else
        return false
        #endif
    }

    static func simPress(input: Input, location: CGPoint, callingFile: String = #fileID, callingFunction: String = #function) {
        guard LoggerService.verboseInputLogging else { return }

        LoggerService.log(file: callingFile, function: callingFunction, [
            "Key: \(input.readable)",
            "Mod: \(input.modifiers)",
            "Loc. X: \(location.x)",
            "Loc. Y: \(location.y)"
        ])
    }

    static func logNotificationError(_ error: Error,
                                     callingFile: String = #fileID,
                                     callingFunction: String = #function) {
        LoggerService.log(file: callingFile, function: callingFunction, [
            "Notification error: \(error.localizedDescription)"
        ])
    }
}
