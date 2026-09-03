import Foundation

/// Last usage band a row alerted at, keyed by `UsageAlertRowKey.storageKey`. Persisted across
/// launches so a relaunch does not re-notify for a row already sitting above the start band.
public struct UsageAlertState: Codable, Sendable, Equatable {
    public private(set) var levels: [String: UsageLevel]

    public init(levels: [String: UsageLevel] = [:]) {
        self.levels = levels
    }

    public init(from decoder: Decoder) throws {
        // Decode as raw strings and drop anything `UsageLevel(rawValue:)` doesn't recognize, so a
        // band name written by a future build only loses that one entry instead of throwing and
        // wiping the whole dictionary (which would re-notify every row on the next refresh).
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: String].self)
        levels = raw.compactMapValues { UsageLevel(rawValue: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(levels.mapValues(\.rawValue))
    }

    public subscript(key: UsageAlertRowKey) -> UsageLevel? {
        get { levels[key.storageKey] }
        set { levels[key.storageKey] = newValue }
    }

    fileprivate mutating func removeStorageKey(_ storageKey: String) {
        levels.removeValue(forKey: storageKey)
    }
}

public final class UsageAlertStateStore: @unchecked Sendable {
    public static let shared = UsageAlertStateStore()
    private let defaults: UserDefaults
    private let key = AppBrand.usageAlertStateKey

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UsageAlertState {
        guard let data = defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(UsageAlertState.self, from: data)
        else {
            return UsageAlertState()
        }
        return state
    }

    public func save(_ state: UsageAlertState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Decides which capped rows just crossed into a new alertable band, and produces the updated state
/// to persist. Pure and `Sendable` so it runs synchronously on the main actor from
/// `MenuBarViewModel.performRefresh` without an extra suspension point.
public enum UsageAlertEvaluator {
    public struct Outcome: Sendable, Equatable {
        public let alerts: [CappedUsageRow]
        public let state: UsageAlertState
    }

    /// - Parameters:
    ///   - rows: capped rows from the fetch just completed (`CappedUsageRows.rows(in:preferences:)`).
    ///   - previous: last-persisted state.
    ///   - startLevel: the lowest band that counts as alertable (`ProviderPreferences.usageAlertStartLevel`).
    ///   - reportingSections: sections that produced a usable report this refresh
    ///     (`CappedUsageRows.reportingSections(in:preferences:)`); a stored band for any other
    ///     section is carried over untouched so a transient error never re-arms it.
    public static func evaluate(
        rows: [CappedUsageRow],
        previous: UsageAlertState,
        startLevel: UsageLevel,
        reportingSections: Set<ProviderSection>
    ) -> Outcome {
        var state = previous
        var alerts: [CappedUsageRow] = []

        // Rows belonging to a section that reported this refresh replace that section's stored keys
        // entirely, so a row that disappeared (a display gate turned off, a window vanished) doesn't
        // linger and block re-arming if it comes back later.
        for storageKey in Array(state.levels.keys) {
            guard let section = Self.section(forStorageKey: storageKey), reportingSections.contains(section) else { continue }
            if rows.contains(where: { $0.key.storageKey == storageKey }) == false {
                state.removeStorageKey(storageKey)
            }
        }

        for row in rows {
            let current = row.level
            let stored = state[row.key]
            if current >= startLevel {
                if stored == nil || current > stored! {
                    alerts.append(row)
                }
                state[row.key] = current
            }
            else if stored != nil {
                // Fell back below the start band (e.g. a window reset) — clear it so climbing back
                // up alerts again instead of staying suppressed at the old band.
                state[row.key] = nil
            }
        }

        return Outcome(alerts: alerts, state: state)
    }

    private static func section(forStorageKey storageKey: String) -> ProviderSection? {
        // storageKey is "<provider>.<kind>.<source>.<label>[#n]"; the section id is the first two
        // dot-separated components (ProviderSection.id format), reconstructed defensively rather
        // than parsed, since only provider/kind combinations that exist can match a live row anyway.
        for provider in ProviderID.allCases {
            for kind in ProviderSectionKind.allCases {
                let section = ProviderSection(provider: provider, kind: kind)
                if storageKey.hasPrefix("\(section.id).") {
                    return section
                }
            }
        }
        return nil
    }
}
