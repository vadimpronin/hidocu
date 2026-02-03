//
//  HiDocuApp.swift
//  HiDocu
//
//  Main entry point for the HiDocu application.
//

import SwiftUI

/// Main application entry point.
/// Initializes the dependency container and provides it to all views.
@main
struct HiDocuApp: App {
    
    /// The app's dependency container (initialized once, lives for app lifetime)
    @State private var container = AppDependencyContainer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withDependencies(container)
        }
        .commands {
            // Add custom menu commands
            CommandGroup(replacing: .newItem) {
                // Hide "New" since we don't support multiple documents
            }
        }
    }
}
