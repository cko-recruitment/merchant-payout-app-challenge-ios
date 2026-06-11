import Foundation

// URLProtocol subclass that intercepts all requests to api.checkout-interview.local.
// Requests will not appear in Charles/Proxyman — use Xcode's console output instead.
//
// Note: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor is set project-wide, making all types
// implicitly @MainActor. The `nonisolated` modifiers below are required to let URLProtocol
// call these overrides from a non-main-actor context.
final class MockURLProtocol: URLProtocol {

    // MARK: - Registration

    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.checkout-interview.local"
    }

    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // MARK: - Request handling

    nonisolated override func startLoading() {
        let client = self.client
        let request = self.request

        Task.detached {
            // Simulate network latency (500–2000 ms)
            let delayNs = UInt64.random(in: 500_000_000...2_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)

            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            let method = request.httpMethod ?? "GET"
            let path = url.path

            do {
                let (data, response) = try self.buildResponse(method: method, path: path, url: url, request: request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    nonisolated override func stopLoading() {}

    // MARK: - Route dispatch

    nonisolated private func buildResponse(
        method: String,
        path: String,
        url: URL,
        request: URLRequest
    ) throws -> (Data, URLResponse) {
        switch (method, path) {
        case ("GET", "/api/merchant"):
            return try jsonResponse(url: url, statusCode: 200, body: MockData.merchant)

        case ("GET", "/api/merchant/activity"):
            let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
            let page = (cursor == nil || cursor == "first") ? MockData.activityPage1 : MockData.activityPage2
            return try jsonResponse(url: url, statusCode: 200, body: page)

        case ("POST", "/api/payouts"):
            return try handlePayout(url: url, request: request)

        default:
            return try jsonResponse(url: url, statusCode: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Payout handler

    nonisolated private func handlePayout(url: URL, request: URLRequest) throws -> (Data, URLResponse) {
        // URLSession converts httpBody → httpBodyStream before routing to URLProtocol,
        // so httpBody is always nil here. Read from the stream instead.
        let bodyData: Data?
        if let httpBody = request.httpBody {
            bodyData = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while true {
                let n = stream.read(buffer, maxLength: 4096)
                if n == 0 { break }
                if n < 0 {
                    throw stream.streamError ?? URLError(.cannotLoadFromNetwork)
                }
                data.append(buffer, count: n)
            }
            bodyData = data
        } else {
            bodyData = nil
        }

        guard
            let body = bodyData,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let amount = json["amount"] as? Int
        else {
            return try jsonResponse(url: url, statusCode: 400, body: ["error": "Bad request"])
        }

        switch amount {
        case 99999:
            return try jsonResponse(url: url, statusCode: 503, body: ["error": "Service temporarily unavailable"])
        case 88888:
            return try jsonResponse(url: url, statusCode: 400, body: ["error": "Insufficient funds"])
        default:
            let currency = (json["currency"] as? String) ?? "GBP"
            let iban = (json["iban"] as? String) ?? ""
            let payout: [String: Any] = [
                "id": "payout_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8).lowercased())",
                "status": "pending",
                "amount": amount,
                "currency": currency,
                "iban": iban,
                "created_at": ISO8601DateFormatter().string(from: Date()),
            ]
            return try jsonResponse(url: url, statusCode: 201, body: payout)
        }
    }

    // MARK: - Response builder

    nonisolated private func jsonResponse(url: URL, statusCode: Int, body: Any) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

// MARK: - Static mock data

private enum MockData {
    // nonisolated(unsafe): read-only after initialisation — safe to access from any isolation context.
    nonisolated(unsafe) static let merchant: [String: Any] = [
        "available_balance": 500000,
        "pending_balance": 25000,
        "currency": "GBP",
        "activity": [
            [
                "id": "act_001",
                "type": "deposit",
                "amount": 150000,
                "currency": "GBP",
                "date": "2026-05-18T10:23:00.000Z",
                "description": "Payment from Customer ABC",
                "status": "completed",
            ],
            [
                "id": "act_002",
                "type": "payout",
                "amount": -50000,
                "currency": "GBP",
                "date": "2026-05-17T14:30:00.000Z",
                "description": "Payout to Bank Account ****1234",
                "status": "completed",
            ],
            [
                "id": "act_003",
                "type": "deposit",
                "amount": 230000,
                "currency": "GBP",
                "date": "2026-05-16T09:15:00.000Z",
                "description": "Payment from Customer XYZ",
                "status": "completed",
            ],
        ],
    ]

    nonisolated(unsafe) static let activityPage1: [String: Any] = [
        "items": [
            ["id": "act_001", "type": "deposit",  "amount":  150000, "currency": "GBP", "date": "2026-05-18T10:23:00.000Z", "description": "Payment from Customer ABC",          "status": "completed"],
            ["id": "act_002", "type": "payout",   "amount":  -50000, "currency": "GBP", "date": "2026-05-17T14:30:00.000Z", "description": "Payout to Bank Account ****1234",   "status": "completed"],
            ["id": "act_003", "type": "deposit",  "amount":  230000, "currency": "GBP", "date": "2026-05-16T09:15:00.000Z", "description": "Payment from Customer XYZ",          "status": "completed"],
            ["id": "act_004", "type": "fee",      "amount":   -2500, "currency": "GBP", "date": "2026-05-15T08:00:00.000Z", "description": "Monthly service fee",               "status": "completed"],
            ["id": "act_005", "type": "payout",   "amount": -120000, "currency": "GBP", "date": "2026-05-14T16:45:00.000Z", "description": "Payout to Bank Account ****5678",   "status": "completed"],
            ["id": "act_006", "type": "deposit",  "amount":   80000, "currency": "GBP", "date": "2026-05-13T11:20:00.000Z", "description": "Payment from Customer DEF",          "status": "completed"],
            ["id": "act_007", "type": "refund",   "amount":  -15000, "currency": "GBP", "date": "2026-05-12T13:10:00.000Z", "description": "Refund to Customer GHI",            "status": "completed"],
            ["id": "act_008", "type": "deposit",  "amount":  320000, "currency": "GBP", "date": "2026-05-11T09:30:00.000Z", "description": "Payment from Customer JKL",          "status": "completed"],
            ["id": "act_009", "type": "payout",   "amount":  -75000, "currency": "GBP", "date": "2026-05-10T17:00:00.000Z", "description": "Payout to Bank Account ****9012",   "status": "completed"],
            ["id": "act_010", "type": "deposit",  "amount":   95000, "currency": "GBP", "date": "2026-05-09T10:45:00.000Z", "description": "Payment from Customer MNO",          "status": "completed"],
            ["id": "act_011", "type": "fee",      "amount":   -1500, "currency": "GBP", "date": "2026-05-08T08:00:00.000Z", "description": "Transaction fee",                   "status": "completed"],
            ["id": "act_012", "type": "payout",   "amount":  -30000, "currency": "GBP", "date": "2026-05-07T15:20:00.000Z", "description": "Payout to Bank Account ****3456",   "status": "completed"],
            ["id": "act_013", "type": "deposit",  "amount":  180000, "currency": "GBP", "date": "2026-05-06T12:00:00.000Z", "description": "Payment from Customer PQR",          "status": "completed"],
            ["id": "act_014", "type": "deposit",  "amount":  110000, "currency": "GBP", "date": "2026-05-05T09:30:00.000Z", "description": "Payment from Customer STU",          "status": "completed"],
            ["id": "act_015", "type": "payout",   "amount":  -60000, "currency": "GBP", "date": "2026-05-04T14:15:00.000Z", "description": "Payout to Bank Account ****7890",   "status": "completed"],
        ],
        "next_cursor": "act_015",
        "has_more": true,
    ]

    nonisolated(unsafe) static let activityPage2: [String: Any] = [
        "items": [
            ["id": "act_016", "type": "deposit",  "amount":  200000, "currency": "GBP", "date": "2026-05-03T10:00:00.000Z", "description": "Payment from Customer VWX",          "status": "completed"],
            ["id": "act_017", "type": "payout",   "amount":  -45000, "currency": "GBP", "date": "2026-05-02T15:30:00.000Z", "description": "Payout to Bank Account ****2345",   "status": "completed"],
            ["id": "act_018", "type": "deposit",  "amount":  170000, "currency": "GBP", "date": "2026-05-01T11:00:00.000Z", "description": "Payment from Customer YZA",          "status": "completed"],
            ["id": "act_019", "type": "refund",   "amount":  -25000, "currency": "GBP", "date": "2026-04-30T09:45:00.000Z", "description": "Refund to Customer BCD",            "status": "completed"],
            ["id": "act_020", "type": "deposit",  "amount":  310000, "currency": "GBP", "date": "2026-04-29T14:00:00.000Z", "description": "Payment from Customer EFG",          "status": "completed"],
            ["id": "act_021", "type": "fee",      "amount":   -2500, "currency": "GBP", "date": "2026-04-28T08:00:00.000Z", "description": "Monthly service fee",               "status": "completed"],
            ["id": "act_022", "type": "payout",   "amount":  -90000, "currency": "GBP", "date": "2026-04-27T16:20:00.000Z", "description": "Payout to Bank Account ****6789",   "status": "completed"],
            ["id": "act_023", "type": "deposit",  "amount":  125000, "currency": "GBP", "date": "2026-04-26T10:10:00.000Z", "description": "Payment from Customer HIJ",          "status": "completed"],
            ["id": "act_024", "type": "deposit",  "amount":  280000, "currency": "GBP", "date": "2026-04-25T13:30:00.000Z", "description": "Payment from Customer KLM",          "status": "completed"],
            ["id": "act_025", "type": "payout",   "amount":  -35000, "currency": "GBP", "date": "2026-04-24T15:00:00.000Z", "description": "Payout to Bank Account ****0123",   "status": "completed"],
            ["id": "act_026", "type": "refund",   "amount":  -10000, "currency": "GBP", "date": "2026-04-23T11:45:00.000Z", "description": "Refund to Customer NOP",            "status": "completed"],
            ["id": "act_027", "type": "deposit",  "amount":  195000, "currency": "GBP", "date": "2026-04-22T09:00:00.000Z", "description": "Payment from Customer QRS",          "status": "completed"],
            ["id": "act_028", "type": "fee",      "amount":   -1500, "currency": "GBP", "date": "2026-04-21T08:00:00.000Z", "description": "Transaction fee",                   "status": "completed"],
            ["id": "act_029", "type": "payout",   "amount":  -55000, "currency": "GBP", "date": "2026-04-20T17:30:00.000Z", "description": "Payout to Bank Account ****4567",   "status": "completed"],
            ["id": "act_030", "type": "deposit",  "amount":  145000, "currency": "GBP", "date": "2026-04-19T12:15:00.000Z", "description": "Payment from Customer TUV",          "status": "completed"],
        ],
        "next_cursor": NSNull(),
        "has_more": false,
    ]
}
