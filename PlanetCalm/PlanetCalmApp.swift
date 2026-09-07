import SwiftUI

@main
struct PlanetCalmApp: App {
    init() {
        PlanetFocusTypography.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
