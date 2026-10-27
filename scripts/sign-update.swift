import Foundation
import CryptoKit
let args = CommandLine.arguments
precondition(args.count == 4, "Usage: sign-update.swift version architecture archive")
let version = args[1], architecture = args[2]
let archive = URL(fileURLWithPath: args[3])
let data = try Data(contentsOf: archive)
let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
let keyPath = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"] ?? "keys/update-signing.key"
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: URL(fileURLWithPath: keyPath)))
// Never emit a package that the distributed updater cannot authenticate.
let pinnedKey = Data(base64Encoded: "MmQwRNZt0R5A05aIAFZPbSEKuUW9CdycPRw1xCZQRwo=")!
guard key.publicKey.rawRepresentation == pinnedKey else { fatalError("Update key does not match the pinned public key") }
let name = archive.lastPathComponent
let message = Data("LSwitcher update v1\n\(version)\n\(architecture)\n\(name)\n\(data.count)\n\(sha)\n".utf8)
let payload: [String: Any] = ["version":version,"architecture":architecture,"filename":name,
    "bytes":data.count,"sha256":sha,"signature":try key.signature(for: message).base64EncodedString()]
try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys,.prettyPrinted])
    .write(to: archive.deletingLastPathComponent().appendingPathComponent("update.json"), options: .atomic)
print("Signed update manifest created; private key remains local.")
