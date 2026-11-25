//
//  TriggerPilotView.swift
//  auto-clicker
//
//  Root of the main window, a 1:1 implementation of node 7:1 "Macro Utility Window".
//  Layer order follows the design: window fill, then two clipped halo ellipses, then the chrome.
//

import SwiftUI

struct TriggerPilotView: View {
    @StateObject private var store = MacroStore.shared
    @StateObject private var runner = MacroRunner.shared
    @StateObject private var counter = TriggerCounter.shared
    @StateObject private var coordinator = MacroRunCoordinator.shared

    @State private var editingMacro: Macro?

    /// The title bar switch reflects the looping macro's run, and flips it when tapped. One-shot
    ///  macros have their own switches in the list and are never driven from here.
    private var isEnabled: Binding<Bool> {
        Binding(
            get: { self.runner.isRunning },
            set: { running in
                if running {
                    self.runner.start()
                } else {
                    self.runner.stop()
                }
            }
        )
    }

    var body: some View {
        ZStack {
            TPPalette.windowBackground

            Halos()

            VStack(spacing: 0) {
                TPTitleBar(isEnabled: self.isEnabled)

                VStack(spacing: TPMetrics.bodySpacing) {
                    TPNoticeBar()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: TPMetrics.macroRowSpacing) {
                            if !self.store.repeatingMacros.isEmpty {
                                self.sectionHeader("macro_section_repeating",
                                                   comment: "Looping macros section header")

                                ForEach(self.store.repeatingMacros) { macro in
                                    TPMacroRow(macro: macro,
                                               isSelected: macro.id == self.store.activeMacro?.id,
                                               onToggleActive: {
                                                   self.store.activate(macro)
                                               },
                                               onEdit: {
                                                   self.editingMacro = macro
                                               })
                                }
                            }

                            if !self.store.oneShotMacros.isEmpty {
                                self.sectionHeader("macro_section_one_shot",
                                                   comment: "One-shot macros section header")

                                ForEach(self.store.oneShotMacros) { macro in
                                    TPMacroRow(macro: macro,
                                               isSelected: macro.isEnabled,
                                               showsSwitch: true,
                                               onToggleActive: {
                                                   self.store.setEnabled(!macro.isEnabled,
                                                                         for: macro.id)
                                               },
                                               onEdit: {
                                                   self.editingMacro = macro
                                               })
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)

                    TPStatsCard(savedCount: self.store.macros.count,
                                activeCount: self.store.activeCount,
                                triggeredToday: self.counter.today)
                }
                .padding(.horizontal, TPMetrics.bodyPadding)
                .padding(.vertical, TPMetrics.bodyPadding)

                TPFootBar(statusText: self.statusText) { activation in
                    self.store.add(activation: activation)
                    self.editingMacro = self.store.macros.last
                }
            }
        }
        .frame(width: TPMetrics.windowWidth, height: TPMetrics.windowHeight)
        .triggerPilotWindowOutline(cornerRadius: TPMetrics.windowCornerRadius)
        // `TPWindowConfigurator` is attached one level up in `ACWindow` so that the window chrome
        //  is configured even while the permissions screen is showing.
        .background(WindowHandleReader())
        .sheet(item: self.$editingMacro) { macro in
            MacroSettingsPanel(macro: macro)
        }
        // The shortcuts are registered here as well as in the app delegate: the delegate fires
        //  before the scene exists, and this view is the first thing that can run after a
        //  permission grant rebuilds the window.
        .onAppear {
            self.runner.registerKeyboardShortcuts()

            // A window left open across midnight would otherwise keep showing yesterday's total.
            self.counter.refresh()
        }
    }

    private func sectionHeader(_ key: String, comment: String) -> some View {
        Text(NSLocalizedString(key, comment: comment))
            .font(TPType.text(10, weight: .medium))
            .foregroundColor(TPPalette.textMuted)
            .padding(.leading, 2)
            .padding(.top, 2)
    }

    private var statusText: String {
        if self.runner.isRunning || self.coordinator.activeRunCount > 0 {
            return NSLocalizedString("macro_status_running", comment: "Macro is running")
        }

        // A start that could not run explains itself here rather than appearing to do nothing.
        if let refusal = self.runner.lastRefusal {
            return refusal
        }

        // The design's "监听中 · 今日 2:40" is a placeholder for a live figure; the count is drawn in
        //  the stats card instead, so the status only reports what the app is doing.
        return NSLocalizedString("macro_status_listening", comment: "Listening status")
    }
}

/// Nodes 2:305 and 2:306. Both ellipses are clipped by the window's rounded rect, which is why
///  their offsets are allowed to fall outside the frame.
private struct Halos: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(TPPalette.accent.opacity(0.16))
                .frame(width: 620, height: 420)
                .offset(x: 60, y: -230)

            Ellipse()
                .fill(TPPalette.halo.opacity(0.07))
                .frame(width: 420, height: 340)
                .offset(x: -180, y: 400)
        }
        .frame(width: TPMetrics.windowWidth, height: TPMetrics.windowHeight)
        .clipped()
        .allowsHitTesting(false)
    }
}

struct TriggerPilotView_Previews: PreviewProvider {
    static var previews: some View {
        TriggerPilotView()
    }
}
