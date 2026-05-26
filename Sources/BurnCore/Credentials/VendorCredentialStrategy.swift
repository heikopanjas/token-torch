import Foundation

/// How subscription OAuth credentials are loaded.
public enum VendorCredentialStrategy: Sendable {
    /// Read vendor stores directly (burn-cli).
    case directVendorRead
    /// Read burn-owned Keychain copy only (menu bar app).
    case burnOwnedCopy
}
