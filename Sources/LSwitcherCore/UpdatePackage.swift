import Foundation
import CryptoKit

public struct UpdatePackage: Codable, Sendable {
    public let version: String
    public let architecture: String
    public let filename: String
    public let bytes: Int
    public let sha256: String
    public let signature: String

    public init(version: String, architecture: String, filename: String, bytes: Int, sha256: String, signature: String) {
        self.version = version; self.architecture = architecture; self.filename = filename
        self.bytes = bytes; self.sha256 = sha256; self.signature = signature
    }

    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    public static func validVersion(_ version: String) -> Bool {
        version.range(of: #"^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$"#, options: .regularExpression) != nil
    }
    public var message: Data {
        Data("LSwitcher update v1\n\(version)\n\(architecture)\n\(filename)\n\(bytes)\n\(sha256)\n".utf8)
    }
    public func validate(current: String, publicKey: Data = signingPublicKey) throws {
        guard Self.validVersion(version), Self.validVersion(current),
              version.compare(current, options: .numeric) == .orderedDescending,
              architecture == Self.architecture,
              filename == "LSwitcher-\(version)-\(architecture).zip",
              (1...25_000_000).contains(bytes),
              sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let signature = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: message) else { throw Failure.invalidPackage }
    }
    public func verify(archive: URL, current: String) throws {
        try validate(current: current)
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == bytes else { throw Failure.invalidPackage }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw Failure.invalidPackage
        }
    }
    public enum Failure: LocalizedError {
        case invalidPackage
        public var errorDescription: String? { "Пакет обновления не прошёл проверку подписи, версии или целостности." }
    }
    public static let signingPublicKey = Data(base64Encoded: "MmQwRNZt0R5A05aIAFZPbSEKuUW9CdycPRw1xCZQRwo=")!
}
