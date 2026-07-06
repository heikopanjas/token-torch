import Foundation

struct CursorPage<Data: Decodable>: Decodable {
    let data: [Data]
    let hasMore: Bool
    let lastID: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case lastID = "last_id"
    }
}

struct NextTokenPage<Bucket: Decodable>: Decodable {
    let data: [Bucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

enum OrgPagination {
    static func appendPageToken(_ token: String?, to baseURLString: String) -> URL {
        var url = baseURLString
        if let token {
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            url += "&page=\(encoded)"
        }
        return URL(string: url)!
    }
}
