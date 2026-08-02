import XCTest
@testable import Teslaris

final class KeyPairTests: XCTestCase {

    /// Tesla fetches a PEM-encoded EC public key on the secp256r1 curve;
    /// CryptoKit's pemRepresentation must match what `openssl ec -pubout`
    /// emits, or registration fails with no useful error.
    func testPublicKeyIsSpkiPEM() {
        let keys = KeyPair.generate()
        XCTAssertTrue(keys.publicPEM.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        XCTAssertTrue(keys.publicPEM.contains("-----END PUBLIC KEY-----"))
        // SPKI for P-256 is 91 bytes → a short, single-block PEM body.
        let body = keys.publicPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let der = Data(base64Encoded: body)
        XCTAssertEqual(der?.count, 91)
        // SPKI header for id-ecPublicKey + prime256v1.
        XCTAssertEqual(der?.prefix(3).map { $0 }, [0x30, 0x59, 0x30])
    }

    func testPrivateKeyIsPKCS8PEM() {
        let keys = KeyPair.generate()
        XCTAssertTrue(keys.privatePEM.hasPrefix("-----BEGIN PRIVATE KEY-----"))
        XCTAssertTrue(keys.privatePEM.contains("-----END PRIVATE KEY-----"))
    }

    func testKeysAreUniquePerCall() {
        XCTAssertNotEqual(KeyPair.generate().publicPEM, KeyPair.generate().publicPEM)
    }

    func testWriteProducesBothFiles() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let keys = KeyPair.generate()
        let publicURL = try KeyPair.write(keys, to: dir)
        XCTAssertEqual(publicURL.lastPathComponent, "com.tesla.3p.public-key.pem")
        XCTAssertTrue(FileManager.default.fileExists(atPath: publicURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("private-key.pem").path))
        XCTAssertEqual(try String(contentsOf: publicURL, encoding: .utf8), keys.publicPEM)
    }

    /// The path is Tesla's, not ours — a typo here breaks every setup.
    func testWellKnownPath() {
        XCTAssertEqual(KeyPair.wellKnownPath,
                       ".well-known/appspecific/com.tesla.3p.public-key.pem")
    }
}
