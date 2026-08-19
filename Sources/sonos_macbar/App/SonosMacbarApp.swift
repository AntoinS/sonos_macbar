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
    }

    var body: some Scene {
        MenuBarExtra("Sonos Macbar", systemImage: "hifispeaker.2.fill") {
            ControlPanelView(state: sonosState)
                .frame(width: 340)
        }
        .menuBarExtraStyle(.window)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
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
