//
//  TeslaOwnerAPI.swift
//  Teslaris
//
//  The easy way in. Tesla's Fleet API demands that every user register
//  their own developer application — key pair, hosted public key, domain
//  ownership, per-region partner registration, a payment method, and a
//  provisioning step that can simply be broken on Tesla's side. That is
//  a lot to ask of someone who wants to see their battery percentage.
//
//  This talks to owner-api.teslamotors.com instead, using the client id
//  Tesla's own mobile app uses. The user signs in and that is all. Tesla
//  has deprecated this API for *commands*, but vehicle data still works
//  — and Teslaris only ever reads.
//
//  The trade-off, stated plainly: this is not a documented integration
//  path and Tesla could close it. Fleet API remains available in
//  Settings for anyone who wants the official route.
//

import Foundation

final class TeslaOwnerAPI: VehicleDataSource {

    private let authBase = "https://auth.tesla.com"
    private let apiBase = "https://owner-api.teslamotors.com"
    /// Tesla's own mobile client. Not a secret — it ships in their app.
    private let clientId = "ownerapi"

    private var accessToken: String?
    private var tokenExpiry: Date?
    /// Owner API addresses cars by numeric id, not VIN, so the mapping
    /// found while listing vehicles has to be kept.
    private var idByVin: [String: String] = [:]
    private(set) var vehicles: [VehicleSummary] = []
    private let session: URLSession

    var isAuthenticated: Bool { accessToken != nil }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private func debugLog(_ message: String) { NSLog("[Teslaris] \(message)") }

    // MARK: - Session

    /// Trades the stored refresh token for an access token. Tesla rotates
    /// refresh tokens, so the newest one is always persisted.
    func restoreSession() async throws {
        guard let refresh = try? Keychain.readOwnerRefreshToken(), !refresh.isEmpty
        else { throw TeslarisError.notConfigured }

        var request = URLRequest(url: URL(string: "\(authBase)/oauth2/v3/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refresh,
            "scope": "openid email offline_access"
        ])

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else {
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog("owner token \(status): \(body.prefix(200))")
            throw TeslarisError.authenticationFailed(
                status == 401 || status == 400
                    ? "that refresh token was rejected — generate a new one"
                    : "couldn't refresh the session (HTTP \(status))")
        }

        accessToken = access
        if let expires = json["expires_in"] as? Int {
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expires))
        }
        if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
            try? Keychain.saveOwnerRefreshToken(newRefresh)
        }
    }

    /// Stores a refresh token pasted by the user and proves it works, so
    /// a bad paste is rejected at entry rather than at the next refresh.
    func signIn(refreshToken: String) async throws {
        let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TeslarisError.notConfigured }
        try Keychain.saveOwnerRefreshToken(trimmed)
        do {
            try await restoreSession()
        } catch {
            Keychain.deleteOwnerRefreshToken()
            throw error
        }
    }

    private func refreshIfNeeded() async throws {
        if let expiry = tokenExpiry, accessToken != nil,
           expiry.timeIntervalSinceNow > 60 { return }
        try await restoreSession()
    }

    // MARK: - Vehicle data

    func fetchVehicleData(vin: String) async throws -> VehicleData {
        try await refreshIfNeeded()
        guard let token = accessToken else { throw TeslarisError.notConfigured }

        if vehicles.isEmpty { try await loadVehicles(token: token) }
        let targetVin = vin.isEmpty ? (vehicles.first?.vin ?? "") : vin
        guard !targetVin.isEmpty else { throw TeslarisError.parse("no vehicles on account") }
        guard let id = idByVin[targetVin] else {
            throw TeslarisError.parse("unknown vehicle \(targetVin)")
        }

        let url = URL(string: "\(apiBase)/api/1/vehicles/\(id)/vehicle_data")!
        let (data, response) = try await authed(url: url, token: token)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        // 408 is Tesla's "vehicle asleep"; never wake it.
        if status == 408 { throw TeslarisError.vehicleAsleep }
        guard status == 200 else { throw TeslarisError.http("vehicle_data returned \(status)") }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vehicle = json["response"] as? [String: Any]
        else { throw TeslarisError.parse("unexpected vehicle_data response") }
        // Same payload shape as Fleet API — Fleet was modelled on this.
        return TeslaFleetAPI.parseVehicleData(vehicle, now: Date())
    }

    private func loadVehicles(token: String) async throws {
        let url = URL(string: "\(apiBase)/api/1/vehicles")!
        let (data, response) = try await authed(url: url, token: token)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["response"] as? [[String: Any]]
        else { throw TeslarisError.http("vehicles list failed") }

        idByVin = [:]
        vehicles = list.compactMap { entry in
            guard let vin = entry["vin"] as? String else { return nil }
            // id_s is the string form; id can lose precision as a Double.
            if let idString = entry["id_s"] as? String {
                idByVin[vin] = idString
            } else if let id = entry["id"] as? NSNumber {
                idByVin[vin] = id.stringValue
            }
            let name = (entry["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let model = CarImage.modelName(vin: vin).map { "Tesla \($0)" }
            return VehicleSummary(vin: vin, title: name ?? model ?? "Tesla")
        }
    }

    private func authed(url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Owner API rejects requests without a recognised user agent.
        request.setValue("Teslaris/1.0", forHTTPHeaderField: "User-Agent")
        return try await session.data(for: request)
    }
}
