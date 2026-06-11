import Foundation

enum Currency: String, Codable { case GBP, EUR }
enum ActivityType: String, Codable { case payout, deposit, refund, fee }
enum ActivityStatus: String, Codable { case completed, pending, processing, failed }
enum PayoutStatus: String, Codable { case pending, processing, completed, failed }

struct ActivityItem: Codable, Identifiable {
    let id: String
    let type: ActivityType
    let amount: Int          // in pence, negative for outflows
    let currency: Currency
    let date: String         // ISO 8601
    let description: String
    let status: ActivityStatus
}

struct MerchantData: Codable {
    let available_balance: Int
    let pending_balance: Int
    let currency: Currency
    let activity: [ActivityItem]
}

struct PaginatedActivityResponse: Codable {
    let items: [ActivityItem]
    let next_cursor: String?
    let has_more: Bool
}

struct PayoutResponse: Codable {
    let id: String
    let status: PayoutStatus
    let amount: Int
    let currency: Currency
    let iban: String
    let created_at: String
}
