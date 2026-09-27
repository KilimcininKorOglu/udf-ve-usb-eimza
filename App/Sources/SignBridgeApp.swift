import SwiftUI

@main
struct SignBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear { model.start() }
        }
    }
}
