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
        let oauthCoordinator = SonosOAuthCoordinator(authClient: authClient, tokenStore: tokenStore, auth: auth)
        let state = SonosState(
            service: SonosService(auth: auth),
            tokenStore: tokenStore,
            oauthCoordinator: oauthCoordinator
        )
        _sonosState = State(initialValue: state)
        OAuthCallbackRouter.shared.handler = { [state] url in
            state.handleOAuthCallback(url)
        }
        SonosMacbarAppDelegate.states = (
            cloud: state,
            local: SonosState(service: SonosLocalService(), connectionMode: .local)
        )
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?
    private var states: [SonosState] = []

    func configure(cloud: SonosState, local: SonosState) {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 1)
        popover.contentViewController = NSHostingController(
            rootView: ControlPanelView(cloudState: cloud, localState: local)
                .frame(width: 340)
        )

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: AppLanguage.english.quitApp,
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )
        menu.items.forEach { $0.target = self }

        self.statusItem = statusItem
        self.popover = popover
        self.contextMenu = menu
        self.states = [cloud, local]
    }

    func popoverWillShow(_ notification: Notification) {
        states.forEach { $0.isPopoverOpen = true }
    }

    func popoverWillClose(_ notification: Notification) {
        states.forEach { $0.isPopoverOpen = false }
    }

    private static func menuBarIcon() -> NSImage? {
        let resourceName = "MenuBarIcon"
        let resourceExtension = "png"
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/AppIcon/menu-bar-icon.png")

        let image = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(contentsOf: sourceURL)
            ?? NSImage(systemSymbolName: "hifispeaker.2.fill", accessibilityDescription: "Sonos Macbar")

        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Sonos Macbar"
        return image
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
        contextMenu.items.first?.title = AppLanguage.current.quitApp
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
    @MainActor static var states: (cloud: SonosState, local: SonosState)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        Task { @MainActor in
            AppUpdater.shared.start()
            guard let states = Self.states else { return }
            StatusBarController.shared.configure(cloud: states.cloud, local: states.local)
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
