import Foundation

struct WarpUsageClient: Sendable {
    // Public Firebase application identifier shipped by Warp, not a user secret.
    static let firebaseAPIKey = "AIzaSyBdy3O3S9hrdayLJxJ7mriBR4qgUaUygAs"
    static let usageURL = URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")!
    static let query = """
    query GetRequestLimitInfo($requestContext: RequestContext!) {
      user(requestContext: $requestContext) {
        ... on UserOutput {
          user {
            requestLimitInfo {
              isUnlimited requestLimit requestsUsedSinceLastRefresh nextRefreshTime requestLimitRefreshDuration
              includedUsageCents usageCentsUsedSinceLastRefresh
            }
          }
        }
        ... on UserFacingError { error { message } }
      }
    }
    """

    let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) { self.http = http }

    func fetchUsage(accessToken: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: .post, url: Self.usageURL,
            headers: ["Authorization": "Bearer \(accessToken)", "Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: [
                "operationName": "GetRequestLimitInfo", "query": Self.query,
                "variables": ["requestContext": [
                    "clientContext": ["version": "v0.2026.10.14.08.27.stable_01"],
                    "osContext": ["category": "macOS", "name": "macOS"]
                ]]
            ])
        ))
    }

    func refreshToken(_ token: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: .post,
            url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Self.firebaseAPIKey)")!,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderParsing.formBody([("grant_type", "refresh_token"), ("refresh_token", token)])
        ))
    }
}
