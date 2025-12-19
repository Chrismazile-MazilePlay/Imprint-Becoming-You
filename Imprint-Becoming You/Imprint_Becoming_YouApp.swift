//
//  Imprint_Becoming_YouApp.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/19/25.
//

import SwiftUI
import SwiftData

@main
struct Imprint_Becoming_YouApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
