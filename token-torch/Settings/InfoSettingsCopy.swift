import Foundation

enum InfoSettingsCopy {
    static let updatesSectionTitle = "Updates"
    static let checkForUpdatesTitle = "Check for Updates…"
    static let automaticChecksTitle = "Automatically check for updates"
    static let automaticDownloadsTitle = "Automatically download and install updates"

    static func versionLine(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    static func copyrightLine(bundle: Bundle = .main) -> String {
        return bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    static var updatesHint: String {
        if AppEnvironment.updatesEnabled == true {
            return "\(AppBrand.displayName) announces a new version with a notification; click it to review and install the update. Updates are signed and verified before they are installed."
        }
        return "Updates are disabled in development builds. Install a release build of \(AppBrand.displayName) to receive updates."
    }
}
