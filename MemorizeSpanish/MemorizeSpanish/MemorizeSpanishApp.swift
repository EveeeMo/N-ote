import SwiftData
import SwiftUI
import UIKit

@main
struct MemorizeSpanishApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [TextbookUnit.self, WordEntry.self, ReviewItem.self, LearningPlanProgress.self])
    }
}
