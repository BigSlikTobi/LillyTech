import SwiftUI

@main
struct LillyTechApp: App {
    init() {
        AppLogger.info("Application starting", category: AppLogger.general)
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    AppLogger.debug("MainView appeared", category: AppLogger.ui)
                }
        }
    }
}
