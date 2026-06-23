import Foundation
import os

/// Unified os.Logger categories for Token Torch diagnostics (no stdout).
public enum TokenTorchLog {
    private static let subsystem = AppBrand.bundleIdentifier

    public static let copilot = Logger(subsystem: subsystem, category: "Copilot")
    public static let http = Logger(subsystem: subsystem, category: "HTTP")
}
