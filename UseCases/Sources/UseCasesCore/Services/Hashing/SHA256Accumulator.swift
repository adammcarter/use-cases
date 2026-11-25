import Crypto

/// SHA-256 from swift-crypto, taken a chunk at a time.
struct SHA256Accumulator: DigestAccumulating {
  private var hash = SHA256()

  mutating func add(_ chunk: [UInt8]) {
    hash.update(data: chunk)
  }

  func hex() -> String {
    hash.finalize()
      .map { byte in
        let hex = String(byte, radix: 16)
        return byte < 16 ? "0" + hex : hex
      }
      .joined()
  }
}
