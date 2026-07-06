import Foundation

enum HTTPHeaders {
    static func bearerJSON(token: String, extra: [String: String] = [:]) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        for (key, value) in extra {
            headers[key] = value
        }
        return headers
    }
}
