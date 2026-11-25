//
//  AppDelegate.swift
//  auto-clicker
//
//  Created by Ben Tindall on 30/03/2022.
//

import Foundation
import Cocoa
import Defaults
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var aboutWindowController: NSWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateService.refreshDockIconState()
        WindowStateService.startObservingWindowState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        // Hacky workaround in SwiftUI in order to have macOS persist the window size state
        // https://stackoverflow.com/a/72558375/4494375
        NSApp.windows.first?.delegate = self

        MenuBarService.refreshState()

        // Registered here rather than only in the view so the shortcuts work while the permissions
        //  screen is up, and so the menu bar's Start/Stop items and the shortcuts share one path.
        MacroRunner.shared.registerKeyboardShortcuts()

        PermissionsService.acquireAccessibilityPrivileges()

        // Initialize mouse start monitoring if enabled
        if Defaults[.mouseStartOnMove] {
            AutoClickSimulator.shared.startMouseStartMonitoring()
        }

        // From here on out we can safely decide whether the dock icon should be shown based on the
        //  state of our windows, so re-apply the preference now that everything is on screen.
        WindowStateService.markFullyLaunched()
        WindowStateService.refreshDockIconState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Hiding the app (Cmd+H, or the menu bar's Hide option) orders out all regular windows, which
        // AppKit then treats as "the last window was closed" and terminates us. Status bar windows do
        // not count as regular windows, so they don't prevent the check. Only quit if we're actually
        // visible and the user has opted in to quitting on close.
        guard !sender.isHidden else {
            return false
        }

        return WindowStateService.shouldExitOnClose()
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        WindowStateService.refreshKeepWindowOnTop()

        // TCC can be changed while the app is running. Refresh on activation so the UI and the
        // permission-gated execution path see the current state.
        PermissionsService.shared.refresh()

        // A TCC grant can arrive while the app is running. Reinstall the read-only global trigger
        //  monitor so keyboard triggers start working without a relaunch.
        MacroTriggerService.shared.restart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cancel work and release any held key/mouse button before the process disappears.
        MacroRunner.shared.stop()
        MacroRunCoordinator.shared.stopAll()
        MacroTriggerService.shared.stop()
        PermissionsService.shared.stopPolling()
    }

    func applicationDidHide(_ notification: Notification) {
        if let hideOrShowMenuItem = MenuBarService.hideOrShowMenuItem {
            hideOrShowMenuItem.title = NSLocalizedString("menu_bar_item_hide_show_show", comment: "Menu bar item show option")
        }
    }

    func applicationDidUnhide(_ notification: Notification) {
        if let hideOrShowMenuItem = MenuBarService.hideOrShowMenuItem {
            hideOrShowMenuItem.title = NSLocalizedString("menu_bar_item_hide_show_hide", comment: "Menu bar item hide option")
        }
    }

    // Hacky workaround in SwiftUI in order to have macOS persist the window size state
    // https://stackoverflow.com/a/72558375/4494375
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !Defaults[.appShouldQuitOnClose] {
            NSApp.hide(nil)
            return false
        }

        return true
    }

    func showAboutWindow() {
        if aboutWindowController == nil {
            let window = NSWindow()

            window.contentView = NSHostingView(rootView: AboutView())

            window.styleMask.insert(.titled)
            window.styleMask.insert(.closable)
            window.styleMask.insert(.fullSizeContentView)

            window.titlebarAppearsTransparent = true

            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = true

            window.isMovableByWindowBackground = true

            window.center()

            aboutWindowController = NSWindowController(window: window)
        }

        aboutWindowController?.showWindow(aboutWindowController?.window)
    }
}
