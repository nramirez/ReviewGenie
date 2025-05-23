//
//  ReviewGenieApp.swift
//  ReviewGenie
//
//  Created by naz on 5/9/25.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct ReviewGenieApp: App {
    var modelContainer: ModelContainer

    init() {
        FirebaseApp.configure()
        print("Firebase configured via App.init()")

        do {
            modelContainer = try ModelContainer(for: VisitRecord.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
        .commands {
            CommandMenu("Actions") {
                Button("Clear All App Data...") {
                    confirmAndDeleteAllData()
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])
            }
        }
    }

    private func confirmAndDeleteAllData() {
        let alert = NSAlert()
        alert.messageText = "Clear All App Data?"
        alert.informativeText = "This will permanently delete all review data from the application. This action cannot be undone."
        alert.addButton(withTitle: "Clear All Data")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task {
                let context = modelContainer.mainContext
                let storageManager = SwiftDataStorageManager(context: context)
                await storageManager.deleteAllData()
                
                await MainActor.run {
                    let completionAlert = NSAlert()
                    completionAlert.messageText = "Data Cleared"
                    completionAlert.informativeText = "All application data has been successfully cleared."
                    completionAlert.addButton(withTitle: "OK")
                    completionAlert.runModal()
                }
            }
        }
    }
}
