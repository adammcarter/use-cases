/// A source of random bits for the part of a run id that keeps two stores apart (chapter 12 §8).
protocol RandomBitsProviding: Sendable {
  /// 64 random bits.
  func next() -> UInt64
}
