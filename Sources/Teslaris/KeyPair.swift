//
//  KeyPair.swift
//  Teslaris
//
//  Generates the EC key pair Tesla requires for a developer application,
//  replacing the two openssl commands from the setup guide. CryptoKit
//  emits exactly what Tesla expects: a P-256 (prime256v1) key whose
//  public half serializes as an SPKI PEM — byte-for-byte what
//  `openssl ec -pubout` produces.
//
//  The private key is generated on this Mac and stays here. Teslaris
//  never uses it (read-only, no vehicle commands); it is saved only so
//  the user keeps it if they later want command support.
//

import CryptoKit
import Foundation

enum KeyPair {

    /// The path Tesla fetches, relative to the user's domain.
    static let wellKnownPath = ".well-known/appspecific/com.tesla.3p.public-key.pem"
    static let publicKeyFilename = "com.tesla.3p.public-key.pem"
    static let privateKeyFilename = "private-key.pem"

    struct Generated {
        let publicPEM: String    // -----BEGIN PUBLIC KEY----- (SPKI)
        let privatePEM: String   // -----BEGIN PRIVATE KEY----- (PKCS#8)
    }

    static func generate() -> Generated {
        let privateKey = P256.Signing.PrivateKey()
        return Generated(publicPEM: privateKey.publicKey.pemRepresentation + "\n",
                         privatePEM: privateKey.pemRepresentation + "\n")
    }

    /// Writes both PEMs into `directory`, returning the public key's URL.
    @discardableResult
    static func write(_ keys: Generated, to directory: URL) throws -> URL {
        let publicURL = directory.appendingPathComponent(publicKeyFilename)
        let privateURL = directory.appendingPathComponent(privateKeyFilename)
        try keys.publicPEM.write(to: publicURL, atomically: true, encoding: .utf8)
        try keys.privatePEM.write(to: privateURL, atomically: true, encoding: .utf8)
        // The private key is secret even though Teslaris never reads it.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: privateURL.path)
        return publicURL
    }
}
