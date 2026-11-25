//
//  MacroSettingsPanel.swift
//  auto-clicker
//
//  1:1 implementation of node 2:410 "Macro Settings Panel" — 400×616 at a 14pt radius.
//

import AppKit
import SwiftUI

struct MacroSettingsPanel: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Macro
    @State private var intervalMilliseconds: Double
    @State private var roundIntervalMilliseconds: Double

    /// The slot currently recording a key press, or `nil` when no capture is in progress.
    @State private var capturingSlot: Int?

    /// Watches for a mouse button while a slot is recording.
    ///
    /// The capture view is a real view rather than a SwiftUI gesture, so a left click has to be
    ///  caught before the overlay's dimming layer sees it. A local monitor runs ahead of the event
    ///  dispatch entirely, which also means a right click is recorded instead of opening a context
    ///  menu.
    @State private var mouseMonitor: Any?

    /// SwiftUI hands first responder status to the first text field of a freshly presented sheet,
    ///  which arrives with its contents selected. The design draws the name field at rest, so the
    ///  selection highlight has to be cleared once the sheet has settled.
    @FocusState private var isNameFocused: Bool

    /// The repeat count as typed. It is kept apart from `draft.repeatCount` so that the field can
    ///  be emptied while the user retypes a number: binding the text straight to the integer would
    ///  snap the field back to the old value the moment it was cleared.
    @State private var repeatText: String = ""

    @FocusState private var isRepeatFocused: Bool

    private let original: Macro

    init(macro: Macro) {
        self.original = macro
        _draft = State(initialValue: macro)
        _intervalMilliseconds = State(initialValue: Double(macro.intervalMilliseconds))
        _roundIntervalMilliseconds = State(initialValue: Double(macro.roundIntervalMilliseconds))
        _repeatText = State(initialValue: String(macro.repeatCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            self.titleBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TPMetrics.panelBodySpacing) {
                    self.nameField
                    self.comboSection
                    self.modeSection
                    self.scopeSection

                    Color.clear.frame(height: 17)

                    DividerHairline(height: 1)

                    self.optionsSection

                    DividerHairline(height: 1, opacity: 0.06)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }

            self.footBar
        }
        .frame(width: TPMetrics.panelWidth, height: TPMetrics.panelHeight)
        .background(TPPalette.panelBackground)
        .triggerPilotWindowOutline(cornerRadius: TPMetrics.windowCornerRadius)
        // The panel's own lights must close the sheet. Minimise and zoom have no meaning for a
        //  sheet, so they are routed to the same dismiss instead of the window behind it.
        .environment(\.performWindowAction) { _ in self.dismiss() }
        // Sheets are their own `NSWindow` and would otherwise paint an opaque square backing
        //  behind the panel's rounded corners.
        .background(PanelWindowConfigurator())
        .onAppear(perform: self.clearInitialFocus)
        // The monitor is owned by this view, so it has to go when the panel does: a surviving
        //  monitor would swallow the next click anywhere in the app.
        .onDisappear(perform: self.stopMouseMonitor)
        .overlay {
            if self.capturingSlot != nil {
                self.captureOverlay
            }
        }
    }

    /// Shown while a slot is recording. The overlay is what holds the keyboard: an invisible AppKit
    ///  view takes first responder so the panel's text field cannot swallow the press. The dimming
    ///  layer is purely decorative — it must not take a click, or recording a mouse button would be
    ///  impossible — so mouse buttons are picked up by a local event monitor instead.
    private var captureOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                Text("macro_capture_prompt", comment: "Key capture prompt")
                    .font(TPType.text(12.5, weight: .medium))
                    .foregroundColor(TPPalette.textPrimary)

                Text("macro_capture_hint", comment: "Key capture cancellation hint")
                    .font(TPType.text(10.5))
                    .foregroundColor(TPPalette.accentMauve)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .triggerPilotSurface(
                fill: TPPalette.surface,
                cornerRadius: TPMetrics.optionRowCornerRadius,
                stroke: TPPalette.accentBright.opacity(0.34)
            )
            .allowsHitTesting(false)

            // Zero-sized: it exists only to hold first responder for keyboard captures.
            KeyCaptureField(onKey: self.apply, onCancel: self.endCapture)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    /// Resigns the first responder the sheet installs on presentation.
    ///
    /// Clearing `isNameFocused` alone is not enough: SwiftUI assigns the responder after the
    ///  view's `onAppear` has already run, so the assignment is deferred to the next run loop pass
    ///  and the window's responder is resigned directly as a backstop.
    private func clearInitialFocus() {
        self.isNameFocused = false

        DispatchQueue.main.async {
            self.isNameFocused = false

            if let window = NSApp.keyWindow,
               window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
            }
        }
    }

    // MARK: - Title bar (2:411)

    private var titleBar: some View {
        TPTitleBarChrome(spacing: 10) {
            Text("macro_settings_title", comment: "Macro settings panel title")
                .font(TPType.text(13, weight: .medium))
                .foregroundColor(TPPalette.textPrimary)
                .lineLimit(1)
        } trailing: {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(TPPalette.accentBright)
                        .frame(width: 5, height: 5)

                    Text("macro_enabled_chip", comment: "Enabled chip")
                        .font(TPType.text(10, weight: .medium))
                        .foregroundColor(TPPalette.accentLabel)
                }
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(TPPalette.accent.opacity(0.18)))

                Button {
                    self.dismiss()
                } label: {
                    CloseGlyph()
                        .stroke(TPPalette.textCool, style: TPMetrics.glyphStrokeMedium)
                        .frame(width: 14, height: 14)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("macro_close", comment: "Close button"))
            }
        }
    }

    // MARK: - Name field (2:425)

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.fieldLabel("macro_field_name", comment: "Macro name field label")

            HStack {
                TextField("", text: self.$draft.name)
                    .textFieldStyle(.plain)
                    .font(TPType.text(12.5))
                    .foregroundColor(TPPalette.textPrimary)
                    .focused(self.$isNameFocused)
                    .padding(.horizontal, 11)
            }
            .frame(height: 36)
            .triggerPilotSurface(
                fill: Color.black.opacity(0.28),
                cornerRadius: TPMetrics.fieldCornerRadius,
                stroke: Color.white.opacity(0.12)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Combo section (2:426)

    private var comboSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                self.fieldLabel("macro_field_combo", comment: "Key combination field label")

                Spacer(minLength: 0)

                Text("\(self.draft.caps.count) / \(Macro.maxCaps)")
                    .font(TPType.mono(11))
                    .foregroundColor(TPPalette.accentLabel)
            }
            .frame(height: 15)

            HStack(spacing: TPMetrics.slotSpacing) {
                ForEach(0 ..< Macro.maxCaps, id: \.self) { index in
                    EditableKeyCapSlot(
                        cap: index < self.draft.caps.count ? self.draft.caps[index] : nil,
                        onCapture: { self.beginCapture(index) },
                        onRemove: { self.removeCap(at: index) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Key capture

    /// Records the next key press into `index`.
    ///
    /// The design keeps every key as its own cap, so a modifier press fills the slot with `CMD`,
    ///  `SHF`, `OPT` or `CTL` and a regular key fills it with that character. Writing into an
    ///  existing slot replaces its key rather than appending, and tapping an empty slot appends.
    private func beginCapture(_ index: Int) {
        self.isNameFocused = false
        self.capturingSlot = index
        self.startMouseMonitor()
    }

    private func endCapture() {
        self.capturingSlot = nil
        self.stopMouseMonitor()
    }

    /// Records a mouse button into the slot being captured and swallows the event, so the click
    ///  cannot also reach the panel underneath.
    private func startMouseMonitor() {
        self.stopMouseMonitor()

        self.mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            // The monitor is torn down by `endCapture`, but a click can still arrive in the gap
            //  between the slot being cleared and the monitor being removed.
            guard self.capturingSlot != nil else {
                return event
            }

            self.apply(event)
            return nil
        }
    }

    private func stopMouseMonitor() {
        guard let monitor = self.mouseMonitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.mouseMonitor = nil
    }

    private func apply(_ event: NSEvent) {
        guard let index = self.capturingSlot else {
            return
        }

        if let cap = KeyCap.captured(from: event) {
            if index < self.draft.caps.count {
                self.draft.caps[index] = cap
            } else if self.draft.caps.count < Macro.maxCaps {
                self.draft.caps.append(cap)
            }
        }

        self.endCapture()
    }

    /// Removing a cap closes the gap so the row always reads left to right, as the design shows.
    private func removeCap(at index: Int) {
        guard index < self.draft.caps.count else {
            return
        }

        self.draft.caps.remove(at: index)
    }

    // MARK: - Mode section (2:427)

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.fieldLabel("macro_field_mode", comment: "Trigger mode field label")

            HStack(spacing: 4) {
                ForEach(TriggerMode.allCases) { mode in
                    let isOn = mode == self.draft.mode

                    Button {
                        self.draft.mode = mode
                    } label: {
                        Text(LocalizedStringKey(mode.localised))
                            .font(TPType.text(11.5, weight: isOn ? .medium : .regular))
                            .foregroundColor(isOn ? .white : TPPalette.textSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: TPMetrics.segmentHeight)
                            .triggerPilotSurface(
                                fill: isOn ? TPPalette.accent : .clear,
                                cornerRadius: TPMetrics.stepperCornerRadius
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(height: 36)
            .triggerPilotSurface(
                fill: Color.black.opacity(0.28),
                cornerRadius: TPMetrics.optionRowCornerRadius
            )

            // A chord presses exactly one key with its modifiers held, so a second regular key has
            //  nowhere to go. Saying so here is what keeps the panel from accepting a macro whose
            //  name describes more than the runner can deliver.
            if self.draft.unsupportedReason != nil {
                Text("macro_error_simultaneous_multi_key", comment: "Simultaneous mode accepts one key")
                    .font(TPType.text(10.5))
                    .foregroundColor(TPPalette.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Execution scope

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.fieldLabel("macro_field_scope", comment: "Execution scope field label")

            HStack(spacing: 4) {
                ForEach(MacroExecutionScope.allCases) { scope in
                    let isOn = scope == self.draft.executionScope

                    Button {
                        self.draft.executionScope = scope
                    } label: {
                        Text(LocalizedStringKey(scope.localised))
                            .font(TPType.text(11.5, weight: isOn ? .medium : .regular))
                            .foregroundColor(isOn ? .white : TPPalette.textSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: TPMetrics.segmentHeight)
                            .triggerPilotSurface(
                                fill: isOn ? TPPalette.accent : .clear,
                                cornerRadius: TPMetrics.stepperCornerRadius
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(height: 36)
            .triggerPilotSurface(
                fill: Color.black.opacity(0.28),
                cornerRadius: TPMetrics.optionRowCornerRadius
            )

            if self.draft.executionScope == .application {
                Menu {
                    ForEach(self.runningApplications, id: \.bundleIdentifier) { application in
                        Button(application.localizedName ?? application.bundleIdentifier ?? "") {
                            self.draft.targetBundleIdentifier = application.bundleIdentifier
                            self.draft.targetApplicationName = application.localizedName
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(self.draft.targetApplicationName
                             ?? NSLocalizedString("macro_scope_select_application", comment: "Select target application"))
                            .font(TPType.text(11.5))
                            .foregroundColor(self.draft.targetBundleIdentifier == nil
                                             ? TPPalette.warning
                                             : TPPalette.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text("▾")
                            .font(TPType.text(11, weight: .medium))
                            .foregroundColor(TPPalette.textCool)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .triggerPilotSurface(
                        fill: TPPalette.surface,
                        cornerRadius: TPMetrics.fieldCornerRadius,
                        stroke: Color.white.opacity(0.12)
                    )
                }
                .menuStyle(.borderlessButton)

                Text("macro_scope_application_hint", comment: "Application scope behavior hint")
                    .font(TPType.text(10.5))
                    .foregroundColor(TPPalette.accentMauve)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular
                    && application.bundleIdentifier != Bundle.main.bundleIdentifier
                    && application.bundleIdentifier != nil
            }
            .sorted {
                ($0.localizedName ?? $0.bundleIdentifier ?? "")
                    .localizedCaseInsensitiveCompare($1.localizedName ?? $1.bundleIdentifier ?? "") == .orderedAscending
            }
    }

    // MARK: - Options section (6:2)

    /// One of the panel's option rows: an icon, a label, a spacer and the control, all sharing the
    ///  same 12pt side padding, height and surface. The height is the only thing that differs
    ///  between them, so it stays a parameter.
    private func optionRow<Content: View>(
        height: CGFloat,
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: spacing, content: content)
            .padding(.horizontal, 12)
            .frame(height: height)
            .triggerPilotSurface(
                fill: TPPalette.surface,
                cornerRadius: TPMetrics.optionRowCornerRadius
            )
    }

    /// The white 12.5pt label every option row uses.
    ///
    /// The key and comment arrive as plain strings, so the lookup goes through `NSLocalizedString`
    ///  rather than `Text(_:comment:)`, whose comment argument must be a literal.
    private func optionLabel(_ key: String, comment: String) -> some View {
        Text(NSLocalizedString(key, comment: comment))
            .font(TPType.text(12.5))
            .foregroundColor(.white)
    }

    /// The muted 11pt label above each field in the panel.
    private func fieldLabel(_ key: String, comment: String) -> some View {
        Text(NSLocalizedString(key, comment: comment))
            .font(TPType.text(11, weight: .medium))
            .foregroundColor(TPPalette.textMuted)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("macro_options_header", comment: "Optional options section header")
                .font(TPType.text(11, weight: .medium))
                .foregroundColor(TPPalette.textMutedBright)

            // 6:5 Option Repeat
            self.optionRow(height: 46, spacing: 10) {
                RepeatGlyph()
                    .frame(width: 15, height: 15)

                self.optionLabel("macro_option_repeat", comment: "Repeat count option")

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    self.stepperButton(glyph: MinusGlyph(), colour: TPPalette.textCool) {
                        self.setRepeatCount(self.draft.repeatCount - 1)
                    }

                    // Typed rather than only stepped: a macro that repeats 200 times is tedious to
                    //  reach one click at a time.
                    TextField("", text: self.$repeatText)
                        .textFieldStyle(.plain)
                        .font(TPType.mono(12))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .focused(self.$isRepeatFocused)
                        .frame(width: 32)
                        .onSubmit(commitRepeatCount)
                        .onChange(of: self.repeatText) { newValue in
                            // Digits only, and the draft follows along so that saving without ever
                            //  leaving the field still keeps what was typed.
                            let digits = newValue.filter { $0.isWholeNumber }

                            if digits != newValue {
                                self.repeatText = digits
                            }

                            if let value = Int(digits) {
                                self.draft.repeatCount = self.clampRepeatCount(value)
                            }
                        }
                        .onChange(of: self.draft.repeatCount) { newValue in
                            // Keeps the field in step with the stepper buttons.
                            let text = String(newValue)

                            if self.repeatText != text {
                                self.repeatText = text
                            }
                        }
                        .onChange(of: self.isRepeatFocused) { focused in
                            if !focused {
                                self.commitRepeatCount()
                            }
                        }

                    self.stepperButton(glyph: PlusGlyph(), colour: TPPalette.accentPale) {
                        self.setRepeatCount(self.draft.repeatCount + 1)
                    }
                }
                .frame(height: 26)
                .triggerPilotSurface(
                    fill: Color.white.opacity(0.09),
                    cornerRadius: TPMetrics.stepperCornerRadius
                )
            }

            // 6:6 Option Delay
            self.optionRow(height: 39, spacing: 10) {
                ClockGlyph()
                    .frame(width: 15, height: 15)

                self.optionLabel("macro_option_delay", comment: "Delay option")

                Spacer(minLength: 0)

                Text(self.delayText)
                    .font(TPType.mono(12))
                    .foregroundColor(TPPalette.textSoft)
                    .layoutPriority(1)

                TPSwitch(isOn: self.$draft.delayEnabled, width: 32, height: 19, onOpacity: 0.85)
            }

            // 6:42 Option Hint Row
            HStack(spacing: 6) {
                LinkGlyph()
                    .frame(width: 12, height: 12)

                Text("macro_option_hint", comment: "Option linkage hint")
                    .font(TPType.text(10.5))
                    .foregroundColor(TPPalette.accentMauve)

                Spacer(minLength: 0)
            }
            .frame(height: 13)

            // The interval only spaces out a sequential macro's presses, so the design hides the
            //  card in the other two modes rather than showing a control that does nothing.
            if self.draft.mode == .sequential {
                self.intervalOption
            }

            // Unlike the interval above, every mode repeats whole rounds, so this card is always
            //  shown.
            self.roundIntervalOption

            DividerHairline(height: 1, opacity: 0.06)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Interval option (6:7)

    private var intervalOption: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                IntervalGlyph()
                    .frame(width: 15, height: 15)

                Text("macro_option_interval", comment: "Sequential interval option")
                    .font(TPType.text(12.5, weight: .medium))
                    .foregroundColor(.white)

                Spacer(minLength: 0)

                Text(self.intervalText)
                    .font(TPType.mono(12))
                    .foregroundColor(TPPalette.accentLavender)
            }
            .frame(height: 16)

            TPSlider(value: self.$intervalMilliseconds, range: 50 ... 2000)

            HStack(spacing: 0) {
                Text("50 ms")
                Spacer(minLength: 0)
                Text("500 ms")
                Spacer(minLength: 0)
                Text("2 s")
            }
            .font(TPType.text(10))
            .foregroundColor(TPPalette.textMuted)
            .frame(height: 12)

            Text("macro_option_interval_hint", comment: "Interval applicability hint")
                .font(TPType.text(10.5))
                .foregroundColor(TPPalette.accentLavenderSoft)
        }
        // The design's card is 92pt tall: 10pt of vertical padding around 16 + 9 + 4 + 9 + 12 + 9 + 13.
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .triggerPilotSurface(
            fill: TPPalette.highlight,
            cornerRadius: TPMetrics.optionRowCornerRadius,
            stroke: TPPalette.accentBright.opacity(0.34)
        )
    }

    // MARK: - Round interval option

    /// The gap between two rounds of the whole combination. It is deliberately built like the
    ///  interval card above — same track, thumb and marks — because the two sliders read as a pair.
    ///  The difference is scope: that one paces the keys inside a round, this one paces the rounds.
    private var roundIntervalOption: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                IntervalGlyph()
                    .frame(width: 15, height: 15)

                Text("macro_option_round_interval", comment: "Round interval option")
                    .font(TPType.text(12.5, weight: .medium))
                    .foregroundColor(.white)

                Spacer(minLength: 0)

                Text(self.roundIntervalText)
                    .font(TPType.mono(12))
                    .foregroundColor(TPPalette.accentLavender)
            }
            .frame(height: 16)

            TPSlider(value: self.$roundIntervalMilliseconds, range: 50 ... 10000)

            HStack(spacing: 0) {
                Text("50 ms")
                Spacer(minLength: 0)
                Text("5 s")
                Spacer(minLength: 0)
                Text("10 s")
            }
            .font(TPType.text(10))
            .foregroundColor(TPPalette.textMuted)
            .frame(height: 12)

            Text("macro_option_round_interval_hint", comment: "Round interval applicability hint")
                .font(TPType.text(10.5))
                .foregroundColor(TPPalette.accentLavenderSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .triggerPilotSurface(
            fill: TPPalette.highlight,
            cornerRadius: TPMetrics.optionRowCornerRadius,
            stroke: TPPalette.accentBright.opacity(0.34)
        )
    }

    /// The repeat count is bounded so that a typo cannot ask the simulator for a run that would
    ///  never finish.
    private func clampRepeatCount(_ value: Int) -> Int {
        min(max(value, Macro.minRepeatCount), Macro.maxRepeatCount)
    }

    /// Drops the keys a mode cannot deliver before the draft is saved.
    ///
    /// A simultaneous chord holds one key, so extra regular keys are removed rather than stored and
    ///  then refused at run time. Mouse caps count as the key of the chord, which is what makes a
    ///  recorded Cmd+click representable. Modifiers are never dropped — they are the chord's flags.
    private func pruneCapsForMode() {
        // Both chord modes deliver exactly one non-modifier cap. Long press used to keep the
        // surplus keys in the UI and silently play only the first one.
        guard self.draft.mode == .simultaneous || self.draft.mode == .longPress else {
            return
        }

        var seenKey = false

        self.draft.caps.removeAll { cap in
            let isKey = !cap.isModifier

            guard isKey else {
                return false
            }

            if seenKey {
                return true
            }

            seenKey = true

            return false
        }
    }

    private func setRepeatCount(_ value: Int) {
        self.draft.repeatCount = self.clampRepeatCount(value)
        self.repeatText = String(self.draft.repeatCount)
    }

    /// Commits whatever is in the field, restoring the last valid count when it was left empty.
    private func commitRepeatCount() {
        guard let value = Int(self.repeatText), !self.repeatText.isEmpty else {
            self.repeatText = String(self.draft.repeatCount)
            return
        }

        self.setRepeatCount(value)
    }

    private func stepperButton<G: Shape>(glyph: G, colour: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph
                .stroke(colour, style: TPMetrics.glyphStrokeMedium)
                .frame(width: 12, height: 12)
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Foot bar (2:413)

    private var footBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button {
                MacroStore.shared.delete(self.original)
                self.dismiss()
            } label: {
                Text("macro_delete", comment: "Delete macro button")
                    .font(TPType.text(12, weight: .medium))
                    .foregroundColor(TPPalette.danger)
                    .frame(width: TPMetrics.deleteButtonWidth, height: TPMetrics.actionButtonHeight)
                    .background(Capsule().fill(TPPalette.dangerFill.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button {
                self.draft.intervalMilliseconds = Int(self.intervalMilliseconds.rounded())
                self.draft.roundIntervalMilliseconds = Int(self.roundIntervalMilliseconds.rounded())
                // The field is committed as well, in case the panel is saved by the button while
                //  the count is still being typed.
                self.commitRepeatCount()
                self.pruneCapsForMode()
                MacroStore.shared.save(self.draft)
                self.dismiss()
            } label: {
                Text("macro_save", comment: "Save macro button")
                    .font(TPType.text(12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: TPMetrics.saveButtonWidth, height: TPMetrics.actionButtonHeight)
                    .background(Capsule().fill(TPPalette.accentSave))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Formatting

    private var delayText: String {
        let seconds = self.draft.delaySeconds
        let formatted = seconds == seconds.rounded() ? "\(Int(seconds))" : String(format: "%.1f", seconds)
        return String(format: NSLocalizedString("macro_delay_value", comment: "Delay value in seconds"), formatted)
    }

    private var intervalText: String {
        "\(Int(self.intervalMilliseconds.rounded())) ms"
    }

    /// Seconds read better than milliseconds once the gap is long, and the slider's own marks
    ///  switch units at the same point.
    private var roundIntervalText: String {
        let milliseconds = Int(self.roundIntervalMilliseconds.rounded())

        if milliseconds < 1000 {
            return "\(milliseconds) ms"
        }

        let seconds = Double(milliseconds) / 1000
        let formatted = seconds == seconds.rounded() ? "\(Int(seconds))" : String(format: "%.1f", seconds)
        return String(format: NSLocalizedString("macro_round_interval_value", comment: "Round interval value in seconds"), formatted)
    }
}

/// Node 6:28 "Slider" — a 4pt track with a 12pt white thumb at 99% radius. The design's filled
///  portion is measured to the thumb's leading edge, so the fill is drawn independently of the
///  thumb rather than as a background behind it.
///
/// The row is only 4pt tall in the design's layout — the thumb deliberately overflows it — so the
///  height here is the track's, not the thumb's.
private struct TPSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let thumbSize: CGFloat = 12
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - self.thumbSize, 1)
            let fraction = (self.value - self.range.lowerBound) / (self.range.upperBound - self.range.lowerBound)
            let offset = usable * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: self.trackHeight)

                Capsule()
                    .fill(TPPalette.accent)
                    .frame(width: offset + self.thumbSize / 2, height: self.trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: self.thumbSize, height: self.thumbSize)
                    .offset(x: offset)
            }
            .frame(width: geo.size.width, height: self.thumbSize)
            .offset(y: (self.trackHeight - self.thumbSize) / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clamped = min(max(gesture.location.x - self.thumbSize / 2, 0), usable)
                        let ratio = clamped / usable
                        self.value = self.range.lowerBound + ratio * (self.range.upperBound - self.range.lowerBound)
                    }
            )
        }
        .frame(height: self.trackHeight)
    }
}

struct MacroSettingsPanel_Previews: PreviewProvider {
    static var previews: some View {
        MacroSettingsPanel(macro: Macro.seed[0])
    }
}
