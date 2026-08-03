//
//  KeyHosting.swift
//  Teslaris
//
//  Tesla insists the developer application's public key be — and remain
//  — reachable at a fixed path on a domain the app registers. Most
//  people have no domain, which made "host this file yourself" the
//  hardest step of setup.
//
//  This uploads the *public* half of a locally generated key pair to a
//  small Cloudflare Worker (source in cloudflare/key-host/) that serves
//  it back on a dedicated subdomain forever. The private key never
//  leaves this Mac, and the public key is public by definition — Tesla
//  fetches it unauthenticated.
//
//  Opting out is one field: host the .pem anywhere and type that domain
//  into Settings instead.
//

import Foundation

enum KeyHosting {

    /// Override for testing against a local `wrangler dev`:
    ///   defaults write com.weareheavy.teslaris debug_key_host_url http://localhost:8787
    private static var endpoint: URL {
        if let override = UserDefaults.standard.string(forKey: "debug_key_host_url"),
           !override.isEmpty, let url = URL(string: "\(override)/v1/keys") {
            return url
        }
        return URL(string: "https://teslaris-keys.weareheavy.dev/v1/keys")!
    }

    /// Uploads the public key and returns the domain now serving it.
    static func host(publicPEM: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-pem-file", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(publicPEM.utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 201,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let domain = json["domain"] as? String, !domain.isEmpty
        else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw TeslarisError.http(detail ?? "key hosting returned \(status)")
        }
        return domain
    }

    /// Confirms the key really is reachable where Tesla will look for it,
    /// so a failure surfaces here rather than as an opaque Tesla error
    /// during registration.
    static func verify(domain: String, expecting publicPEM: String) async -> Bool {
        guard let url = URL(string: "https://\(domain)/\(KeyPair.wellKnownPath)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let served = String(data: data, encoding: .utf8)
        else { return false }
        return served.trimmingCharacters(in: .whitespacesAndNewlines)
            == publicPEM.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where the private key is kept. Teslaris never reads it; it is
    /// saved so the user still has it if they later want Tesla's
    /// command API, which does need it.
    static func privateKeyURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("Teslaris", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(KeyPair.privateKeyFilename)
    }
}
