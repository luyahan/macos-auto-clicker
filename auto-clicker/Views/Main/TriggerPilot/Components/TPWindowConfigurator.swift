//
//  TPWindowConfigurator.swift
//  auto-clicker
//
//  The window is drawn entirely by SwiftUI: the design puts its own traffic lights 14pt from the
//  top-left corner, which is exactly where AppKit reserves space for the real ones. Leaving both
//  in place would stack two sets of buttons on top of each other, so the standard buttons are
//  hidden here and `TrafficLights` takes over their behaviour.
//
//  Hiding them means the drawn lights must stay functional, otherwise the window could not be
//  closed or moved. `TrafficLights` therefore always performs the real action regardless of
//  whether this configurator has run.
//
//  The actions it performs must not be the `perform…` family: those all consult the style mask
//  first and quietly do nothing once `.titled` has been dropped, which is what made every light
//  inert. See `WindowHandle.perform(_:)`.
//

import AppKit
import ObjectiveC
import SwiftUI

/// Lets a borderless window become key again.
///
/// A window whose `styleMask` lacks `.titled` refuses to become key, and a window that cannot
///  become key never receives mouse or keyboard events: the UI renders, but every click is
///  swallowed and the app cannot even be brought to the front. Dropping `.titled` is still required
///  for the design's exact 420x620 geometry, so the capability has to be restored by other means.
///
/// Swapping the instance's class with `object_setClass` is the obvious approach and is wrong: AppKit
///  registers KVO observers on every window (`_NSTouchBarFinderObservation`), and a changed `isa`
///  makes those observers throw while the window is torn down, aborting the process the moment a
///  sheet was opened.
///
/// Swizzling the two getters leaves every object's class untouched and only changes the answer they
///  return, which existing observers tolerate. Windows opt in explicitly, and everything else keeps
///  the stock behaviour.
enum WindowKeyability {
    /// The windows that opted in. Weak, so this never keeps a closed window alive.
    private static let optedIn = NSHashTable<NSWindow>.weakObjects()

    private static var installed = false

    static func optIn(_ window: NSWindow) {
        self.installIfNeeded()
        self.optedIn.add(window)
    }

    fileprivate static func hasOptedIn(_ window: NSWindow) -> Bool {
        self.optedIn.contains(window)
    }

    private static func installIfNeeded() {
        guard !self.installed else {
            return
        }

        self.installed = true

        self.swizzle(
            original: #selector(getter: NSWindow.canBecomeKey),
            replacement: #selector(NSWindow.ac_canBecomeKey)
        )

        // Also required. AppKit marks a borderless window as neither key nor main, and SwiftUI reads
        //  `canBecomeMain` to decide whether the scene still has a usable window. With it false the
        //  scene concludes its window is gone and builds a second one, which is why two identical
        //  420x620 windows appeared at launch.
        self.swizzle(
            original: #selector(getter: NSWindow.canBecomeMain),
            replacement: #selector(NSWindow.ac_canBecomeMain)
        )
    }

    private static func swizzle(original: Selector, replacement: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(NSWindow.self, original),
            let replacementMethod = class_getInstanceMethod(NSWindow.self, replacement)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

private extension NSWindow {
    /// Runs in place of the stock getter once swizzled. Only windows that opted in are overridden;
    ///  after the exchange this call reaches the original implementation, not itself.
    @objc func ac_canBecomeKey() -> Bool {
        if WindowKeyability.hasOptedIn(self) {
            return true
        }

        return self.ac_canBecomeKey()
    }

    @objc func ac_canBecomeMain() -> Bool {
        if WindowKeyability.hasOptedIn(self) {
            return true
        }

        return self.ac_canBecomeMain()
    }
}

/// The window styling both of the app's windows share.
///
/// The main window and the settings sheet are configured identically apart from how their size is
///  pinned, so those steps live here once instead of being copied into two configurators.
struct WindowChrome {
    /// How the window's size is held at the design's dimensions.
    enum Sizing {
        /// The main window. `setFrame` rather than `setContentSize`, otherwise AppKit adds the
        ///  title bar strip back on top of the design height. The top edge is held still so the
        ///  window does not appear to jump when the height is corrected.
        case frame

        /// The settings sheet, which AppKit sizes through its content view.
        case content
    }

    /// The app's main window: the design's own 420x620.
    static let main = WindowChrome(
        designSize: NSSize(width: TPMetrics.windowWidth, height: TPMetrics.windowHeight),
        sizing: .frame
    )

    /// The settings sheet: the design's own 400x616.
    static let panel = WindowChrome(
        designSize: NSSize(width: TPMetrics.panelWidth, height: TPMetrics.panelHeight),
        sizing: .content
    )

    let designSize: NSSize
    let sizing: Sizing

    /// Applies everything the two windows have in common, then pins the size.
    func apply(to window: NSWindow) {
        // The rounded corners are drawn by SwiftUI, so the window itself must not paint a square
        //  background behind them.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // `.hiddenTitleBar` hides the title bar's appearance, but AppKit still reserves its height
        //  in the layout. That is why the window measured 420x652 instead of the design's 420x620:
        //  SwiftUI sized the *content* area to 620 and AppKit added the title bar strip on top.
        //
        // Measured before the style is changed, because the strip collapses once `.titled` is gone
        //  and the height would no longer be recoverable.
        let chromeHeight = max(0, min(60, window.frame.height - window.contentLayoutRect.height))

        // `.fullSizeContentView` lets the content view cover the title bar strip, so the drawn
        //  SwiftUI chrome starts at the window's real top edge.
        window.styleMask.insert(.fullSizeContentView)

        // The decisive fix. `.titled` is what makes AppKit reserve the title bar strip, and while
        //  it is present SwiftUI re-derives the window height as "content + title bar" after every
        //  resize below, which is why the window kept snapping back to 652pt.
        //
        // Nothing is lost by dropping it: both windows draw their own title bar and traffic lights,
        //  and this configurator hides AppKit's. `WindowDragArea` supplies the dragging and
        //  `WindowKeyability` puts key events back, so the borderless windows still behave normally.
        window.styleMask.remove(.titled)

        // Restores what `.titled` used to provide implicitly. Without it the window can no longer
        //  become key, and every click in the UI is silently discarded.
        WindowKeyability.optIn(window)

        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        // Hiding the standard buttons also removes the only draggable region, so the window
        //  background itself has to accept drags.
        window.isMovableByWindowBackground = true
        window.isMovable = true

        // Pinning the *content* size to the design height minus the title bar strip makes the frame
        //  land exactly on the design's dimensions while the content view still fills all of it.
        let contentSize = NSSize(
            width: self.designSize.width,
            height: max(1, self.designSize.height - chromeHeight)
        )

        let apply: () -> Void
        switch self.sizing {
        case .frame:
            apply = {
                window.contentMinSize = contentSize
                window.contentMaxSize = contentSize

                var frame = window.frame
                let topEdge = frame.maxY
                frame.size = self.designSize
                frame.origin.y = topEdge - self.designSize.height
                window.setFrame(frame, display: true)
            }

        case .content:
            apply = {
                window.contentMinSize = contentSize
                window.contentMaxSize = contentSize
                window.setContentSize(contentSize)
            }
        }

        apply()
        // SwiftUI commits its own layout size after this view is first installed, so the pin has to
        //  be repeated on the next run loop pass.
        DispatchQueue.main.async(execute: apply)
    }
}

/// Runs a `WindowChrome` against the window that hosts a representable's view.
enum WindowChromeInstaller {
    /// The window does not exist until the view is in a hierarchy, so the work is deferred a run
    ///  loop pass rather than run against a nil window.
    static func attach(to view: NSView, _ configure: @escaping (NSWindow) -> Void) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            configure(window)
        }
    }
}

/// Configures the app's main window.
struct TPWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        WindowChromeInstaller.attach(to: view) { WindowChrome.main.apply(to: $0) }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        WindowChromeInstaller.attach(to: nsView) { WindowChrome.main.apply(to: $0) }
    }
}

/// How a window narrows the actions its `TrafficLights` cluster offers.
enum WindowActionAvailability {
    /// The window is pinned to its design size, so its green light has nothing to zoom to.
    ///  Applied by `ACWindow` alongside `TPWindowConfigurator`.
    static let fixedSize: (WindowAction) -> Bool = { $0 != .zoom }
}

/// Reports the window's backing `NSWindow` so `TrafficLights` can drive it.
///
/// Not an `ObservableObject`: the window is captured once and never read during a view update, so
///  there is no published state for a view to re-render on.
final class WindowHandle {
    static let shared = WindowHandle()

    weak var window: NSWindow?

    private init() {}

    func perform(_ action: WindowAction) {
        guard let window = self.window ?? NSApp.keyWindow else {
            return
        }

        switch action {
        case .close:
            self.close(window)

        case .miniaturise:
            // `miniaturize(nil)` rather than `performMiniaturize(nil)`: the latter checks the style
            //  mask, finds no `.miniaturizable` once `.titled` is gone, and returns without doing
            //  anything. This call has no such check.
            window.miniaturize(nil)

        case .zoom:
            // Same reason as above: `performZoom(nil)` consults the style mask, `zoom(nil)` does
            //  not.
            window.zoom(nil)
        }
    }

    /// Closes the window the way the red light is expected to.
    ///
    /// `performClose(nil)` is a no-op here: it refuses to close unless the style mask still holds
    ///  `.closable`, and removing `.titled` takes that with it. `close()` has no such check, but it
    ///  also bypasses the delegate — and the delegate is where "close means hide" lives — so the
    ///  delegate is consulted by hand first.
    private func close(_ window: NSWindow) {
        // `nil` means the window has no delegate, or has one that does not answer.
        let delegateWantsToClose = window.delegate?.windowShouldClose?(window)

        if delegateWantsToClose ?? WindowStateService.shouldExitOnClose() {
            window.close()
        } else if delegateWantsToClose == nil {
            // The delegate refused the close and already handled it. When there was no answer to
            //  refuse, the same hide-instead-of-quit fallback has to be applied here.
            NSApp.hide(nil)
        }
    }
}

enum WindowAction {
    case close
    case miniaturise
    case zoom
}

/// How a `TrafficLights` cluster should act on its window.
///
/// The settings panel is presented as a sheet, so its own lights must close the *sheet* rather than
/// the window behind it, and the minimise/zoom actions have no meaning for a sheet at all. Making
/// the behaviour an environment value keeps `TrafficLights` reusable for both windows instead of
/// having it reach for `WindowHandle.shared` and always hit the main window.
private struct WindowActionKey: EnvironmentKey {
    static let defaultValue: (WindowAction) -> Void = { WindowHandle.shared.perform($0) }
}

extension EnvironmentValues {
    var performWindowAction: (WindowAction) -> Void {
        get { self[WindowActionKey.self] }
        set { self[WindowActionKey.self] = newValue }
    }
}

/// Whether an action can do anything for the window a `TrafficLights` cluster belongs to.
///
/// Every action is available by default. A window that cannot honour one narrows it with
///  `WindowActionAvailability`. Drawing a control that silently does nothing is worse than one that
///  reads as unavailable, so the cluster asks before it wires the action up.
private struct WindowActionAvailabilityKey: EnvironmentKey {
    static let defaultValue: (WindowAction) -> Bool = { _ in true }
}

extension EnvironmentValues {
    var isWindowActionAvailable: (WindowAction) -> Bool {
        get { self[WindowActionAvailabilityKey.self] }
        set { self[WindowActionAvailabilityKey.self] = newValue }
    }
}

/// Configures the sheet that hosts `MacroSettingsPanel`.
///
/// A sheet is an `NSWindow` of its own, so it paints its own opaque backing behind the SwiftUI
/// content. Because the panel draws a 14pt rounded rect, that backing showed up as square corners
/// and a light band around the panel. Clearing it lets the panel's own background be the only thing
/// drawn, exactly like the main window does.
struct PanelWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        WindowChromeInstaller.attach(to: view, Self.configure)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        WindowChromeInstaller.attach(to: nsView, Self.configure)
    }

    private static func configure(_ window: NSWindow) {
        WindowChrome.panel.apply(to: window)

        // The name field must be reachable by clicking, but a sheet otherwise presents itself with
        //  that field already focused and its text fully selected. The design draws the field at
        //  rest, and the selection highlight also reads as a rendering defect. Refusing the initial
        //  responder keeps the field editable without the highlight.
        window.initialFirstResponder = nil

        for _ in 0 ..< 2 {
            DispatchQueue.main.async {
                if let responder = window.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
}

/// Records the hosting window for `WindowHandle` without changing anything about it.
struct WindowHandleReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        WindowChromeInstaller.attach(to: view) { WindowHandle.shared.window = $0 }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        WindowChromeInstaller.attach(to: nsView) { WindowHandle.shared.window = $0 }
    }
}

/// A transparent strip that drags the hosting window. `isMovableByWindowBackground` alone is not
///  enough: SwiftUI's hosting view consumes the mouse-down before AppKit's background dragging
///  ever sees it, so the drag has to be claimed by an AppKit view of our own.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DraggableView: NSView {
    /// Claim the drag for the window instead of for this view.
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    /// Let a click that lands on an inactive window start dragging straight away, rather than
    ///  being swallowed as the click that merely activates the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        self.window?.performDrag(with: event)
    }
}
