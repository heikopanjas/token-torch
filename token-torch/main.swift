import AppKit

// PTY repair children must become a controlling-terminal session leader before AppKit starts.
PseudoTerminalChildBootstrap.runIfRequested()

// `--capture-usage-responses <directory>` writes raw usage responses and exits without starting the menu bar UI.
UsageResponseCapture.runIfRequested()

// main.swift top-level code is the process entry point.
// Retain delegate for app lifetime (`NSApplication.delegate` is weak).
private nonisolated(unsafe) var tokenTorchAppDelegate: AppDelegate!

tokenTorchAppDelegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = tokenTorchAppDelegate
app.run()
