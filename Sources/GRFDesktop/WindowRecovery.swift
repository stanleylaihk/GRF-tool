import AppKit
import SwiftUI

@MainActor
public protocol MainWindowHandle: AnyObject {
    var isMiniaturized: Bool { get }
    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: MainWindowHandle {}

@MainActor
public final class WindowRecovery {
    public weak var window: (any MainWindowHandle)?
    public var createWindow: () -> Void
    public var activate: () -> Void
    public init(createWindow: @escaping () -> Void = {}, activate: @escaping () -> Void = {}) {
        self.createWindow = createWindow
        self.activate = activate
    }
    public func reopen() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            createWindow()
        }
        activate()
    }
}

@MainActor
public final class GRFApplicationDelegate: NSObject, NSApplicationDelegate {
    public let recovery = WindowRecovery()
    public var mayTerminate: () -> Bool = { true }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { mayTerminate() ? .terminateNow : .terminateCancel }
    private weak var registeredWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    public override init() {
        super.init()
        recovery.activate = {
            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        recovery.reopen()
        return false
    }

    public func register(_ window: NSWindow) {
        guard registeredWindow !== window else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        registeredWindow = window
        window.isMovableByWindowBackground = true
        recovery.window = window
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recovery.window = nil
                self?.registeredWindow = nil
            }
        }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
}

/// Register only the archive window, never an open/save panel or an auxiliary window.
public struct MainWindowCapture: NSViewRepresentable {
    private let delegate: GRFApplicationDelegate
    public init(delegate: GRFApplicationDelegate) { self.delegate = delegate }
    public func makeNSView(context: Context) -> NSView {
        let view = WindowCaptureView()
        view.register = { [weak delegate] window in delegate?.register(window) }
        return view
    }
    public func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { delegate.register(window) }
    }
}

private final class WindowCaptureView: NSView {
    var register: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { register?(window) }
    }
}

/// A native drag surface behind toolbar controls. Interactive SwiftUI controls
/// receive their own events; otherwise empty toolbar space moves the window.
public struct WindowDragRegion: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSView { WindowDragView() }
    public func updateNSView(_ view: NSView, context: Context) {}
}

final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
