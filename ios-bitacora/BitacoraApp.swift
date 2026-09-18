/*  BitacoraApp.swift — the shell. Deliberately tiny: the app IS the logbook, and every screen
    it has is a screen index.html already draws. What lives natively is only what a web page
    cannot do for itself — the durable vault, haptics, the share sheet, and a real app icon on
    the home screen instead of a bookmark. */
import SwiftUI

@main
struct BitacoraApp: App {
    var body: some Scene {
        WindowGroup {
            LogbookView()
                .ignoresSafeArea()          // the page owns its own insets via env(safe-area-inset-*)
                .background(Color(red: 0.086, green: 0.031, blue: 0.063))  // --bg, so a cold launch is wine, never white
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
