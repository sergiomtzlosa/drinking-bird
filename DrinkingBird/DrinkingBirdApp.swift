import SwiftUI

@main
struct DrinkingBirdApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 660)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
    }
}
