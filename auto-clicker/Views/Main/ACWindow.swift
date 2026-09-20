//
//  ACWindow.swift
//  auto-clicker
//
//  Created by Ben Tindall on 16/07/2022.
//

import SwiftUI
import Defaults

struct ACWindow: View {
    @Default(.appearanceSelectedTheme) private var activeTheme

    @StateObject private var permissionsService = PermissionsService.shared

    var body: some View {
        ZStack {
            if self.permissionsService.isTrusted {
                TriggerPilotView()
            } else {
                self.activeTheme.backgroundColour.ignoresSafeArea()

                PermissionsView()
            }
        }
        // The window reserves a title bar strip even though `.hiddenTitleBar` makes it invisible.
        //  Without this the SwiftUI content is inset below that strip, which showed up as an empty
        //  band above the design's own title bar.
        .ignoresSafeArea()
        // Window chrome configuration lives here rather than inside `TriggerPilotView` so that it
        //  also applies while the permissions screen is showing — otherwise the window would keep
        //  the stock title bar (and its extra height) until permissions were granted.
        .background(TPWindowConfigurator())
        // The window is pinned to the design's 420x620, so the drawn green light has nothing to
        //  zoom to and is shown as unavailable.
        .environment(\.isWindowActionAvailable, WindowActionAvailability.fixedSize)
        .onAppear {
            self.permissionsService.pollAccessibilityPrivileges(onTrusted: {
                MenuBarService.enableAllMenuBarItems()
            })
        }
    }
}
