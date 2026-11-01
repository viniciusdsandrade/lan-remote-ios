import SwiftUI

@main
struct LanRemoteApp: App {
    @StateObject private var client = LGTVClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RemoteView(client: client)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the background (or from Settings, after allowing local network access): look
            // for the TV now instead of on the next 10 s tick.
            if phase == .active {
                Task { await client.refreshStatus() }
            }
        }
    }
}
