//
//  OMSDemoApp.swift
//  OMSDemo
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import SwiftUI

@main
struct OMSDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.automatic)
        .defaultSize(width: 984, height: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
