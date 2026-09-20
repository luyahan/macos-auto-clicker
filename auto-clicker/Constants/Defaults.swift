//
//  Defaults.swift
//  auto-clicker
//
//  Created by Ben Tindall on 30/03/2022.
//

import Foundation
import Cocoa
import Defaults

extension Defaults.Keys {
    static let appShouldQuitOnClose = Key<Bool>("app_should_quit_on_close", default: true)

    static let windowShouldKeepOnTop = Key<Bool>("window_should_keep_on_top", default: false)

    static let menuBarShowIcon = Key<Bool>("menu_bar_show_icon", default: true)
    static let menuBarShowDynamicIcon = Key<Bool>("menu_bar_show_dynamic_icon", default: false)
    static let menuBarHideDock = Key<Bool>("menu_bar_hide_dock", default: false)
    static let menuBarHideDockOnClose = Key<Bool>("menu_bar_hide_dock_on_close", default: true)

    static let appearanceSelectedTheme = Key<ThemeService>("appearance_selected_theme", default: ThemeService())

    static let autoClickerState = Key<FormState>("user_form_state", default: FormState())

    static let macros = Key<[Macro]>("macro_list", default: [])

    static let activeMacroID = Key<UUID?>("macro_active_id", default: nil)

    /// Marks that the seed macros have already been offered to the user once.
    ///
    /// Seeding and the initial activation used to be decided from `macros.isEmpty` and
    ///  `activeMacroID == nil`, which are both legitimate states a user can reach on purpose: delete
    ///  every macro, or click the armed row to disarm it. Both then came back on the next launch.
    ///  A dedicated flag distinguishes "never initialised" from "deliberately empty".
    static let macrosSeeded = Key<Bool>("macro_list_seeded", default: false)

    /// Backing store for the stats card's "今日触发" figure. The day is kept alongside the count so
    ///  that a total recorded yesterday is discarded rather than shown as today's.
    static let triggerCountToday = Key<Int>("macro_trigger_count", default: 0)
    static let triggerCountDay = Key<String>("macro_trigger_day", default: "")

    static let notifyOnStart = Key<Bool>("notify_on_start", default: false)
    static let notifyOnFinish = Key<Bool>("notify_on_finish", default: false)

    static let mouseStopOnMove = Key<Bool>("mouse_stop_on_move", default: false)
    static let mouseStartOnMove = Key<Bool>("mouse_start_on_move", default: false)
    static let mouseDeltaThreshold = Key<Int>("mouse_delta_threshold", default: MIN_MOUSE_MOVEMENT_THRESHOLD)
}
