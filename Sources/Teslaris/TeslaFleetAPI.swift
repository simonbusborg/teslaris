//
//  TeslaFleetAPI.swift
//  Teslaris
//
//  Client for Tesla's official Fleet API. Each user brings their own
//  (free) Tesla developer application — client ID from Preferences,
//  client secret from the Keychain — so usage bills against their own
//  $10/month credit and Teslaris itself has no server and no costs.
//
//  Read-only by design: the only scope requested is vehicle_device_data.
//  Sleeping vehicles are never woken (wakes cost money and battery);
//  a 408 surfaces as .vehicleAsleep and the UI shows cached data.
//

import AppKit
import Network

final class TeslaFleetAPI: VehicleDataSource {

    // MARK: - Endpoints

    /// OAuth host. China uses auth.tesla.cn — not supported yet.
    private let authBase = "https://auth.tesla.com"
    /// Local loopback the user registers as their app's redirect URI.
    static let redirectURI = "http://localhost:8973/callback"
    static let callbackPort: UInt16 = 8973
    private let scopes = "openid offline_access vehicle_device_data"

    private var apiBase: String {
        // Developer override for the local mock server:
        //   defaults write com.weareheavy.teslaris debug_base_url http://localhost:4321
        if let override = UserDefaults.standard.string(forKey: "debug_base_url"),
           !override.isEmpty { return override }
        return Preferences.region.apiBase
    }

    private var tokenEndpoint: String {
        if let override = UserDefaults.standard.string(forKey: "debug_base_url"),
           !override.isEmpty { return "\(override)/oauth2/v3/token" }
        return "\(authBase)/oauth2/v3/token"
    }

    // MARK: - State

    private var accessToken: String?
    private var tokenExpiry: Date?
    private(set) var vehicles: [VehicleSummary] = []
    private let session: URLSession

    var isAuthenticated: Bool { accessToken != nil }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private func debugLog(_ message: String) {
        NSLog("[Teslaris] \(message)")
    }

    // MARK: - OAuth

    /// Full interactive sign-in: opens the Tesla consent page in the
    /// default browser and catches the redirect on a local listener.
    /// Runs the authorization-code flow with the user's own client.
    func signIn() async throws {
        let clientId = Preferences.clientId
        guard !clientId.isEmpty,
              let secret = try? Keychain.readClientSecret(), !secret.isEmpty
        else { throw TeslarisError.notConfigured }

        let state = UUID().uuidString
        var components = URLComponents(string: "\(authBase)/oauth2/v3/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state)
        ]

        async let codeTask = Self.waitForCallback(expectedState: state)
        NSWorkspace.shared.open(components.url!)
        let code = try await codeTask

        try await exchangeToken(params: [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "client_secret": secret,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "audience": Preferences.region.apiBase
        ])
    }

    /// Resume from the stored refresh token without user interaction.
    func restoreSession() async throws {
        guard let refresh = try? Keychain.readRefreshToken(), !refresh.isEmpty
        else { throw TeslarisError.notConfigured }
        try await exchangeToken(params: [
            "grant_type": "refresh_token",
            "client_id": Preferences.clientId,
            "refresh_token": refresh
        ])
    }

    private func refreshTokenIfNeeded() async throws {
        if let expiry = tokenExpiry, accessToken != nil,
           expiry.timeIntervalSinceNow > 60 { return }
        try await restoreSession()
    }

    private func exchangeToken(params: [String: String]) async throws {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TeslarisError.http("no response") }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog("token endpoint \(http.statusCode): \(body.prefix(300))")
            throw TeslarisError.authenticationFailed("token endpoint returned \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { throw TeslarisError.parse("unexpected token response") }

        accessToken = access
        if let expires = json["expires_in"] as? Int {
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expires))
        }
        // Tesla rotates refresh tokens on every use — always persist the
        // newest one, or the session dies after the first refresh.
        if let newRefresh = json["refresh_token"] as? String {
            try? Keychain.saveRefreshToken(newRefresh)
        }
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.sorted().joined(separator: "&")
    }

    // MARK: - OAuth callback listener

    /// One-shot HTTP listener on localhost that catches the OAuth redirect,
    /// answers with a tiny "you can close this tab" page, and returns the code.
    static func waitForCallback(expectedState: String,
                                port: UInt16 = callbackPort) async throws -> String {
        let listener = try NWListener(using: .tcp,
                                      on: NWEndpoint.Port(rawValue: port)!)
        defer { listener.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let finish: (Result<String, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1,
                                   maximumLength: 16_384) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let result = Self.parseCallback(request: request, expectedState: expectedState)

                    let body = "<html><body style='font-family:-apple-system;padding:2em'>"
                        + "<h2>Teslaris</h2><p>You can close this tab and return to the app.</p>"
                        + "</body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
                        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8),
                                    completion: .contentProcessed { _ in
                        connection.cancel()
                        // Browsers often prefetch or request /favicon.ico —
                        // only settle on a request that carried a result.
                        if let result { finish(result) }
                    })
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { finish(.failure(error)) }
            }
            listener.start(queue: .main)
        }
    }

    /// Extracts the code from the raw HTTP request line, verifying state.
    /// Returns nil for unrelated requests (favicon etc.).
    static func parseCallback(request: String, expectedState: String) -> Result<String, Error>? {
        guard let line = request.components(separatedBy: "\r\n").first,
              line.hasPrefix("GET "),
              let path = line.components(separatedBy: " ").dropFirst().first,
              path.hasPrefix("/callback")
        else { return nil }

        guard let components = URLComponents(string: "http://localhost\(path)") else {
            return .failure(TeslarisError.authenticationFailed("bad callback URL"))
        }
        let value: (String) -> String? = { name in
            components.queryItems?.first(where: { $0.name == name })?.value
        }
        if let error = value("error") {
            return .failure(TeslarisError.authenticationFailed(error))
        }
        guard value("state") == expectedState else {
            return .failure(TeslarisError.authenticationFailed("state mismatch"))
        }
        guard let code = value("code") else {
            return .failure(TeslarisError.authenticationFailed("no code in callback"))
        }
        return .success(code)
    }

    // MARK: - Vehicle data

    func fetchVehicleData(vin: String) async throws -> VehicleData {
        try await refreshTokenIfNeeded()
        guard let token = accessToken else { throw TeslarisError.notConfigured }

        if vehicles.isEmpty { try await loadVehicles(token: token) }
        let targetVin = vin.isEmpty ? (vehicles.first?.vin ?? "") : vin
        guard !targetVin.isEmpty else { throw TeslarisError.parse("no vehicles on account") }

        // endpoints filter keeps the payload (and the bill) small.
        let url = URL(string: "\(apiBase)/api/1/vehicles/\(targetVin)/vehicle_data"
            + "?endpoints=charge_state%3Bvehicle_state")!
        let (data, response) = try await authed(url: url, token: token)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 408 { throw TeslarisError.vehicleAsleep }
        guard status == 200 else { throw TeslarisError.http("vehicle_data returned \(status)") }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vehicle = json["response"] as? [String: Any]
        else { throw TeslarisError.parse("unexpected vehicle_data response") }
        return Self.parseVehicleData(vehicle, now: Date())
    }

    private func loadVehicles(token: String) async throws {
        let url = URL(string: "\(apiBase)/api/1/vehicles")!
        let (data, response) = try await authed(url: url, token: token)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["response"] as? [[String: Any]]
        else { throw TeslarisError.http("vehicles list failed") }

        vehicles = list.compactMap { entry in
            guard let vin = entry["vin"] as? String else { return nil }
            let name = (entry["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return VehicleSummary(vin: vin, title: name ?? "Tesla")
        }
    }

    private func authed(url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: request)
    }

    /// Parses the `response` object of vehicle_data. Static and pure so the
    /// whole thing is testable from fixtures without a car.
    static func parseVehicleData(_ vehicle: [String: Any], now: Date) -> VehicleData {
        let charge = vehicle["charge_state"] as? [String: Any] ?? [:]
        let state = vehicle["vehicle_state"] as? [String: Any] ?? [:]

        func kmFromMiles(_ value: Any?) -> Int? {
            let miles: Double?
            if let d = value as? Double { miles = d }
            else if let i = value as? Int { miles = Double(i) }
            else { miles = nil }
            guard let miles else { return nil }
            return Int((miles * 1.609344).rounded())
        }

        let minutes = charge["minutes_to_full_charge"] as? Int
        return VehicleData(
            batteryPercentage: (charge["battery_level"] as? NSNumber)?.doubleValue ?? 0,
            rangeKm: kmFromMiles(charge["battery_range"]) ?? 0,
            chargingState: charge["charging_state"] as? String ?? "Unknown",
            minutesToFull: (minutes ?? 0) > 0 ? minutes : nil,
            chargeLimitPercent: charge["charge_limit_soc"] as? Int,
            chargingPowerKw: charge["charger_power"] as? Int,
            vehicleName: (vehicle["display_name"] as? String)
                ?? (state["vehicle_name"] as? String),
            vin: vehicle["vin"] as? String,
            odometerKm: kmFromMiles(state["odometer"]),
            isAsleep: false,
            lastUpdated: now
        )
    }
}
