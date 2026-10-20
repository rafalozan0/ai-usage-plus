import Foundation

struct DroidUsageClient: Sendable {
    static let refreshURL = URL(string: "https://api.workos.com/user_management/authenticate")!
    static let clientID = "client_01HNM792M5G5G1A2THWPXKFMXB"
    let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) { self.http = http }

    func fetchUsage(auth: DroidAuth) async throws -> HTTPResponse {
        let host = auth.region == "eu" ? "api.eu.factory.ai" : "api.factory.ai"
        var headers = ["Authorization": "Bearer \(auth.accessToken)", "Accept": "application/json",
                       "X-Factory-Client": "cli", "X-Client-Version": "0.218.1"]
        if let organizationID = auth.organizationID { headers["X-Factory-Org-Id"] = organizationID }
        return try await http.send(HTTPRequest(method: .get,
            url: URL(string: "https://\(host)/api/billing/limits")!, headers: headers))
    }

    func refreshToken(_ token: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(method: .post, url: Self.refreshURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderParsing.formBody([("grant_type", "refresh_token"),
                                           ("refresh_token", token), ("client_id", Self.clientID)])))
    }
}
