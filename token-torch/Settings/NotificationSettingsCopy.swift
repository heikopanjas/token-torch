enum NotificationSettingsCopy {
    static let usageAlertsSectionTitle = "Usage alerts"

    static let notifyOnUsageThresholdHint =
        "Alerts as soon as a limit enters the starting band, then again at each higher band it reaches — orange, red, then deep red. Dropping back to a lower band (e.g. a window reset) re-arms it."

    static func startLevelTitle(_ level: UsageLevel) -> String {
        "\(level.alertDisplayName) (\(Int(level.thresholdPercent))% used)"
    }
}
