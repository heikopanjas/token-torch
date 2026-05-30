import AppKit

// main.swift top-level code is the process entry point.
// Retain delegate for app lifetime (`NSApplication.delegate` is weak).
private nonisolated(unsafe) var tokenTorchAppDelegate: AppDelegate!

tokenTorchAppDelegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = tokenTorchAppDelegate
app.run()
