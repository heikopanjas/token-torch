import Foundation

enum FlexibleDoubleDecoding {
    static func decode<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) throws -> Double {
        if let number = try? container.decode(Double.self, forKey: key) {
            return number
        }
        if let text = try? container.decode(String.self, forKey: key),
            let parsed = Double(text)
        {
            return parsed
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "invalid numeric value"
        )
    }
}
