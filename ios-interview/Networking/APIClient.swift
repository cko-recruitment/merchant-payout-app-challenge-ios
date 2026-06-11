import Foundation

enum API {
    nonisolated static let baseURL = URL(string: "http://api.checkout-interview.local")!

    // Pre-configured URLSession that routes through MockURLProtocol.
    // Use this (or URLSession.shared after registering MockURLProtocol) for all API calls.
    nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }()
}
