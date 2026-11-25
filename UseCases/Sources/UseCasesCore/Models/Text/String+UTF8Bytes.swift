extension String {
  /// The text of bytes that are strict UTF-8, kept exactly: a leading byte-order mark stays, which
  /// `String(bytes:encoding:)` may drop. Bytes that are not UTF-8 are repaired, so callers check
  /// `isStrictUTF8` first.
  init(utf8Bytes bytes: [UInt8]) {
    self.init(unsafeUninitializedCapacity: bytes.count) { buffer in
      _ = buffer.initialize(from: bytes)

      return bytes.count
    }
  }
}
