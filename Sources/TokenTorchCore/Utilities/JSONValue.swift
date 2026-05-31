import Foundation

/// Minimal recursive JSON value used to decode provider fields whose exact shape is undocumented
/// (e.g. ChatGPT `promo`). Lets us surface unknown keys as notes without hard-coding a schema.
public indirect enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        }
        else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        }
        else if let value = try? container.decode(Double.self) {
            self = .number(value)
        }
        else if let value = try? container.decode(String.self) {
            self = .string(value)
        }
        else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        }
        else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// `true` when the value carries no information worth displaying.
    public var isEmpty: Bool {
        switch self {
            case .null: true
            case .object(let dict): dict.isEmpty
            case .array(let items): items.isEmpty
            default: false
        }
    }

    /// Flattens scalar leaves into ordered `(path, value)` pairs, skipping nulls.
    /// Nested keys are dot-joined onto `prefix` for readable note labels.
    public func flattenedScalars(prefix: String = "") -> [(label: String, value: String)] {
        switch self {
            case .null:
                return []
            case .string(let value):
                return [(prefix, value)]
            case .bool(let value):
                return [(prefix, value ? "yes" : "no")]
            case .number(let value):
                return [(prefix, Self.formatNumber(value))]
            case .object(let dict):
                return dict.sorted { $0.key < $1.key }.flatMap { key, child in
                    child.flattenedScalars(prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
                }
            case .array(let items):
                return items.enumerated().flatMap { index, child in
                    child.flattenedScalars(prefix: "\(prefix)[\(index)]")
                }
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
