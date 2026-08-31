import SwiftUI

@main
struct SourceGrabberApp: App {
    @StateObject private var historyStore = HistoryStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyStore)
        }
    }
}
