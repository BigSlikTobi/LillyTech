import SwiftUI

@main
struct LillyTechApp: App {
    init() {
        AppLogger.shared.info("Application starting", category: AppLogger.shared.general)
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    AppLogger.shared.debug("MainView appeared", category: AppLogger.shared.ui)
                }
        }
    }
}
