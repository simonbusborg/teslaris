//
//  UsageMeter.swift
//  Teslaris
//
//  Counts billed Fleet API data requests per calendar month — for the
//  menu's transparency row and the polling brake. ~$0.002 per request
//  at Tesla's published rate; the authoritative ledger is Tesla's
//  developer dashboard, this is a local estimate.
//

import Foundation

enum UsageMeter {
    private static let countKey = "api_request_count"
    private static let monthKey = "api_request_month"

    private static var currentMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    /// Call once per billed data request (vehicle list, vehicle data).
    /// Auth-endpoint traffic is not billed and not counted.
    static func record() {
        let defaults = UserDefaults.standard
        let month = currentMonth
        if defaults.string(forKey: monthKey) != month {
            defaults.set(month, forKey: monthKey)
            defaults.set(0, forKey: countKey)
        }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static var monthlyCount: Int {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: monthKey) == currentMonth else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    /// "$0.34" — at Tesla's ~$1 per 500 data requests.
    static func estimatedCost(requests: Int) -> String {
        String(format: "$%.2f", Double(requests) * 0.002)
    }
}
