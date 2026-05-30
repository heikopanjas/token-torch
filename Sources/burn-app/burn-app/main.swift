import AppKit

// main.swift top-level code is the process entry point.
// Retain delegate for app lifetime (`NSApplication.delegate` is weak).
private nonisolated(unsafe) var burnAppDelegate: AppDelegate!

burnAppDelegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = burnAppDelegate
app.run()
