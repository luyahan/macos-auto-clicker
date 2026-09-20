//
//  AutoClickerApp.swift
//  auto-clicker
//
//  Created by Ben Tindall on 12/05/2021.
//

import Foundation
import SwiftUI
import Defaults

@main
struct AutoClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ACWindow()
                .frame(minWidth: WindowStateService.mainWindowMinWidth,
                       idealWidth: WindowStateService.mainWindowMinWidth,
                       maxWidth: WindowStateService.mainWindowMinWidth * WindowStateService.mainWindowMaxDimensionMultiplier,
                       minHeight: WindowStateService.mainWindowMinHeight,
                       idealHeight: WindowStateService.mainWindowMinHeight,
                       maxHeight: WindowStateService.mainWindowMinHeight)
        }
        .windowStyle(.hiddenTitleBar)
        // `.contentSize` would size the *content* area to 620 and let AppKit add the title bar
        //  strip on top, producing a 652pt window. `TPWindowConfigurator` pins both the content
        //  size and the frame instead, so SwiftUI must not also manage them.
        .windowResizability(.contentMinSize)
        .commands {
            HelpCommands()

            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button(NSLocalizedString("about_about", comment: "About") + " \(Bundle.main.appName)...") { delegate.showAboutWindow() }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
