import Foundation
import CryptoKit

// Reads only the supplied release secret. Does not use or modify the Keychain.
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let text = String(data: input, encoding: .utf8),
      let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), seed.count == 32,
      let expected = ProcessInfo.processInfo.environment["ARES_UPDATE_PUBLIC_KEY"],
      let publicKey = Data(base64Encoded: expected) else {
    fatalError("Use a dedicated Sparkle Ed25519 seed and public key")
}
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
guard privateKey.publicKey.rawRepresentation == publicKey else {
    fatalError("Update public/private keys do not match")
}
print("Update signing key pair verified")
