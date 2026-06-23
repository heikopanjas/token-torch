import Foundation

public enum QuotaAuthPolicy: Sendable {
    case strict
    case standard
    case extended
}

public enum QuotaHTTP {
    private static func containsHTTPStatus(_ message: String, code: Int) -> Bool {
        message.contains("(\(code))") || message.contains("(\(code) ")
    }

    public static func isQuotaAuthError(_ error: Error, policy: QuotaAuthPolicy) -> Bool {
        let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        if containsHTTPStatus(msg, code: 401) || msg.contains("authentication_error") { return true }
        switch policy {
            case .strict:
                return false
            case .standard:
                return containsHTTPStatus(msg, code: 403) || msg.contains("token refresh")
            case .extended:
                return containsHTTPStatus(msg, code: 403) || msg.contains("token refresh") || msg.contains("expired")
        }
    }

    public static func isQuotaRateLimitError(_ error: Error) -> Bool {
        let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return msg.contains("429") || msg.contains("rate_limit")
    }

    /// Fails fast for a session whose access token is already expired.
    ///
    /// Token Torch is read-only and never refreshes vendor tokens, so calling the usage API with an
    /// expired token only yields a 401 (and the retry churn can trigger a 429). Surface the precise
    /// re-login message up front instead.
    public static func requireUsableSession(_ session: OAuthSession, provider: String, vendorAction: String) throws {
        guard VendorCredentialsReader.sessionIsUsable(session) else {
            throw VendorCredentialsReader.quotaSessionExpired(
                provider: provider, session: session, vendorAction: vendorAction
            )
        }
    }

    public static func fetchWithAuthRecovery(
        provider: String,
        session: OAuthSession,
        vendorAction: String,
        policy: QuotaAuthPolicy,
        reauthenticate: (() throws -> OAuthSession)? = nil,
        fetch: (OAuthSession) async throws -> SubscriptionQuotaReport
    ) async throws -> SubscriptionQuotaReport {
        do {
            return try await fetch(session)
        }
        catch {
            if isQuotaAuthError(error, policy: policy), let reauthenticate {
                let newSession = try reauthenticate()
                do {
                    return try await fetch(newSession)
                }
                catch let retryError {
                    if isQuotaAuthError(retryError, policy: policy) {
                        throw VendorCredentialsReader.quotaSessionExpired(
                            provider: provider, session: newSession, vendorAction: vendorAction
                        )
                    }
                    throw retryError
                }
            }
            if isQuotaAuthError(error, policy: policy) {
                throw VendorCredentialsReader.quotaSessionExpired(
                    provider: provider, session: session, vendorAction: vendorAction
                )
            }
            throw error
        }
    }

    public static func parseQuotaResponse<T: Decodable>(
        data: Data,
        statusCode: Int,
        operation: String
    ) throws -> T {
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200 ..< 300).contains(statusCode) else {
            throw TokenTorchError.message("\(operation) failed (\(statusCode)): \(Redaction.redactSecrets(text))")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        }
        catch {
            throw TokenTorchError.message(
                "Invalid \(operation) response: \(Redaction.redactSecrets(text))"
            )
        }
    }
}

public struct HTTPClient: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getJSON<T: Decodable>(url: URL, headers: [String: String] = [:]) async throws -> T {
        let (data, http) = try await data(for: url, method: "GET", headers: headers)
        return try QuotaHTTP.parseQuotaResponse(data: data, statusCode: http.statusCode, operation: "GET \(url.absoluteString)")
    }

    public func data(
        for url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenTorchError.message("Invalid HTTP response")
        }
        return (data, http)
    }

    public func postJSON<T: Decodable>(
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body ?? Data("{}".utf8)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenTorchError.message("Invalid HTTP response")
        }
        return try QuotaHTTP.parseQuotaResponse(data: data, statusCode: http.statusCode, operation: "POST \(url.path)")
    }

    public func paginateCursor<T: Decodable>(
        baseURL: URL,
        limit: Int,
        cursorParam: String,
        headers: [String: String] = [:],
        onPage: (T, Int) -> (hasMore: Bool, nextCursor: String?),
        pageCallback: ((Int) -> Void)? = nil
    ) async throws {
        var cursor: String?
        var pageNumber = 0
        let client = self
        while true {
            pageNumber += 1
            pageCallback?(pageNumber)
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor { items.append(URLQueryItem(name: cursorParam, value: cursor)) }
            components.queryItems = items
            guard let url = components.url else { break }
            let page: T = try await client.getJSON(url: url, headers: headers)
            let (hasMore, next) = onPage(page, pageNumber)
            if !hasMore || next == nil { break }
            cursor = next
        }
    }

    public func paginateNextToken<T: Decodable>(
        urlBuilder: (String?) -> URL,
        headers: [String: String] = [:],
        onPage: (T, Int) -> (hasMore: Bool, nextToken: String?),
        pageCallback: ((Int) -> Void)? = nil
    ) async throws {
        var nextPage: String?
        var pageNumber = 0
        let client = self
        while true {
            pageNumber += 1
            pageCallback?(pageNumber)
            let page: T = try await client.getJSON(url: urlBuilder(nextPage), headers: headers)
            let (hasMore, next) = onPage(page, pageNumber)
            if !hasMore || next == nil { break }
            nextPage = next
        }
    }
}
