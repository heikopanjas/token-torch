import Foundation

/// Facts about the process the app runs in.
enum AppEnvironment {
    /// True when the app hosts the unit test bundle; the app then never starts the Sparkle updater.
    static let isRunningUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return environment["XCTestBundlePath"] != nil
    }()

    /// Debug builds never check for updates, so a development build is not replaced by the published release.
    static let isDebugBuild: Bool = {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }()

    /// Sparkle runs only in Release builds outside the unit test host.
    static var updatesEnabled: Bool {
        return Self.isRunningUnitTests == false && Self.isDebugBuild == false
    }
}
