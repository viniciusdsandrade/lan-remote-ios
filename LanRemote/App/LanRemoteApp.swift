import SwiftUI

@main
struct LanRemoteApp: App {
    @StateObject private var client = LGTVClient()
    
    var body: some Scene {
        WindowGroup {
            RemoteView(client: client)
                .preferredColorScheme(.dark)
        }
    }
}
