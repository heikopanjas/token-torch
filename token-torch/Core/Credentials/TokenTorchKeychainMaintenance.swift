import Foundation

/// Destructive maintenance for Token Torch-owned Keychain items.
///
/// Only items whose service begins with ``AppBrand/keychainServicePrefix`` (`com.tokentorch.`) are
/// ever removed — that is the admin keys (`com.tokentorch.keys.*`) and the imported vendor OAuth
/// copies (`com.tokentorch.vendor.*`). Vendor-owned logins (Claude Code, Codex, Cursor) live under
/// their own service names and are never affected.
public enum TokenTorchKeychainMaintenance {
    /// Returns `true` when `service` is one Token Torch created and may safely be deleted.
    public static func isTokenTorchService(_ service: String) -> Bool {
        service.hasPrefix(AppBrand.keychainServicePrefix)
    }

    /// Deletes every Token Torch-owned Keychain item, returning the number removed.
    @discardableResult
    public static func resetTokenTorchKeychain() -> Int {
        KeychainReader.deleteItems(withServicePrefix: AppBrand.keychainServicePrefix)
    }
}
