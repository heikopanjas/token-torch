import Foundation

/// How subscription OAuth credentials are loaded.
public enum VendorCredentialStrategy: Sendable {
    /// Read vendor stores directly (token-torch-cli).
    case directVendorRead
    /// Read Token Torch-owned Keychain copy only (menu bar app).
    case tokenTorchOwnedCopy
}
