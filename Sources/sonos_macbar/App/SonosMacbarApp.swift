import AppKit
import SwiftUI

@main
struct SonosMacbarApp: App {
    @NSApplicationDelegateAdaptor(SonosMacbarAppDelegate.self) private var appDelegate
    @State private var sonosState: SonosState

    init() {
        let tokenStore = SonosTokenStore()
        let authClient = SonosAuthClient()
        let auth = SonosAuth(authClient: authClient, tokenStore: tokenStore)
        let oauthCoordinator = SonosOAuthCoordinator(authClient: authClient, tokenStore: tokenStore)
        let state = SonosState(
            service: SonosService(auth: auth),
            tokenStore: tokenStore,
            oauthCoordinator: oauthCoordinator
        )
        _sonosState = State(initialValue: state)
        OAuthCallbackRouter.shared.handler = { [state] url in
            state.handleOAuthCallback(url)
        }
        SonosMacbarAppDelegate.state = state
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?

    func configure(state: SonosState) {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "hifispeaker.2.fill",
                accessibilityDescription: "Sonos Macbar"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 1)
        popover.contentViewController = NSHostingController(
            rootView: ControlPanelView(state: state)
                .frame(width: 340)
        )

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Quit Sonos Macbar",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )
        menu.items.forEach { $0.target = self }

        self.statusItem = statusItem
        self.popover = popover
        self.contextMenu = menu
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let statusItem, let contextMenu else { return }

        popover?.performClose(nil)
        statusItem.menu = contextMenu
        button.performClick(nil)
        statusItem.menu = nil
    }
}

@MainActor
private final class OAuthCallbackRouter {
    static let shared = OAuthCallbackRouter()
    var handler: ((URL) -> Void)?

    func handle(_ url: URL) {
        handler?(url)
    }
}

private final class SonosMacbarAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var state: SonosState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        Task { @MainActor in
            guard let state = Self.state else { return }
            StatusBarController.shared.configure(state: state)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        Task { @MainActor in
            OAuthCallbackRouter.shared.handle(url)
        }
    }
}
