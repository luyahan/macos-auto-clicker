//
//  WindowStateService.swift
//  auto-clicker
//
//  Created by Ben Tindall on 30/03/2022.
//

import Foundation
import Cocoa
import Defaults

struct WindowStateService {
    static let mainWindowMinWidth: CGFloat = 600
    static let mainWindowMinHeight: CGFloat = 430
    static let mainWindowMaxDimensionMultiplier: CGFloat = 1.3

    static let settingsMinWidth: CGFloat = 600

    static let menuBarWidth: CGFloat = 150
    static let menuBarHeight: CGFloat = 500

    static func toggleKeepWindowOnTop(_ keepOnTop: Bool) {
        // This is somewhat finiky... I originally used NSApplication.shared.mainWindow as it contained the primary window
        //   but this has problems when using the preferences window as when the preferences window is open it becomes the
        //   mainWindow. So reverting back to NSApplication.shared.windows.first as the 'main' application window will be
        //   the first to load and take that place. BUT, it only works with applicationShouldTerminateAfterLastWindowClosed
        //   returning true, as the main window is never re-created due to the app just being terminated when it is closed.
        // If this behaviour is ever changed, then I'll need to somehow track the 'main' application window in the array of
        //   running application windows.
        if let window = NSApplication.shared.windows.first {
            if keepOnTop {
                window.level = .floating
            } else {
                window.level = .normal
            }
        }
    }

    static func refreshKeepWindowOnTop() {
        self.toggleKeepWindowOnTop(Defaults[.windowShouldKeepOnTop])
    }

    static func shouldExitOnClose() -> Bool {
        Defaults[.appShouldQuitOnClose]
    }

    static func toggleDockIcon(showIcon: Bool) -> Bool {
        NSApp.setActivationPolicy(self.activationPolicy(showIcon: showIcon))
    }

    private static func activationPolicy(showIcon: Bool) -> NSApplication.ActivationPolicy {
        showIcon ? .regular : .accessory
    }

    static func refreshDockIconState() {
        let showIcon = !self.shouldHideDockIcon

        // `setActivationPolicy` is not free, and this gets called from window notifications, so skip the
        //  call when nothing actually changed. Reading the policy back from AppKit rather than caching it
        //  keeps us from drifting out of sync with the real state.
        guard NSApp.activationPolicy() != self.activationPolicy(showIcon: showIcon) else {
            return
        }

        _ = self.toggleDockIcon(showIcon: showIcon)
    }

    /// Same as `refreshDockIconState()` but evaluated on the next run loop pass. AppKit posts its hide and
    ///  unhide notifications before it has finished ordering the windows, so reading `isVisible` straight
    ///  away can give a stale answer and leave the dock icon in the wrong state.
    static func refreshDockIconStateDeferred() {
        DispatchQueue.main.async {
            self.refreshDockIconState()
        }
    }

    /// Restores the regular activation policy so the app can activate itself and present its windows.
    /// This is required before bringing the main window back, as an app using the `.accessory` policy
    /// cannot reliably do either.
    static func prepareForShowingWindows() {
        // If the dock icon is hidden permanently then leave it alone, the user asked for that.
        guard !Defaults[.menuBarHideDock] else {
            return
        }

        _ = self.toggleDockIcon(showIcon: true)
    }

    private static var isObservingWindowState = false

    /// Watches the hide/unhide and window events that can change whether the app has a window on screen.
    /// Relying on the app delegate alone isn't enough, as SwiftUI can order the main window back in without
    ///  going through the usual unhide path.
    static func startObservingWindowState() {
        guard !self.isObservingWindowState else {
            return
        }

        self.isObservingWindowState = true

        let center = NotificationCenter.default

        // Cmd+H, the menu bar's Hide option, and our own `NSApp.hide` on close all land here.
        center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            self.refreshDockIconStateDeferred()
        }

        center.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { _ in
            self.prepareForShowingWindows()
            self.refreshDockIconStateDeferred()
        }

        // Safety net: however the app comes back to the foreground (Dock click, `open`, the menu bar's
        //  Show option, a SwiftUI scene activation), we get a chance to restore the dock icon.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            self.refreshDockIconStateDeferred()
        }

        // Window level events, so the icon comes back however the window is re-shown. Status bar and other
        //  helper windows report `canBecomeMain == false` and are filtered out.
        let appearingNotifications: [Notification.Name] = [
            NSWindow.didBecomeMainNotification,
            NSWindow.didDeminiaturizeNotification
        ]

        let disappearingNotifications: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.willCloseNotification
        ]

        for name in appearingNotifications {
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow, window.canBecomeMain else {
                    return
                }

                // A window is back, so make sure we can activate ourselves before re-evaluating the icon.
                self.prepareForShowingWindows()
                self.refreshDockIconStateDeferred()
            }
        }

        for name in disappearingNotifications {
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow, window.canBecomeMain else {
                    return
                }

                self.refreshDockIconStateDeferred()
            }
        }
    }

    private static var shouldHideDockIcon: Bool {
        // An explicit "always hide the dock icon" preference always wins.
        if Defaults[.menuBarHideDock] {
            return true
        }

        // With no menu bar icon there would be no way back into the app, so never hide the dock icon.
        guard Defaults[.menuBarShowIcon] else {
            return false
        }

        // Before the app has finished launching there is no window to judge visibility from, so only the
        //  permanent preference above applies. This stops the icon flashing in/out during startup.
        guard self.isFullyLaunched, Defaults[.menuBarHideDockOnClose] else {
            return false
        }

        // Cmd+H and the "close without quitting" path both hide the whole app.
        if NSApplication.shared.isHidden {
            return true
        }

        // Otherwise hide the icon only when no regular window is on screen (e.g. the main window was closed).
        return !self.hasVisibleAppWindow
    }

    private static var hasVisibleAppWindow: Bool {
        // Miniaturized windows are not "visible" as far as AppKit is concerned, but the user still has a
        //  window in the Dock, so count those too.
        NSApplication.shared.windows.contains {
            $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }
    }

    private static var isFullyLaunched = false

    static func markFullyLaunched() {
        self.isFullyLaunched = true
    }
}
