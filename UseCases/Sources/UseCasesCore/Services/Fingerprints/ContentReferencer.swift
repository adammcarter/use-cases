struct ContentReferencer: ContentReferencing {
  private let normalizer: any ContentNormalizing
  private let digester: any FingerprintDigesting
  private let hasher: any Hashing

  init(
    normalizer: any ContentNormalizing,
    digester: any FingerprintDigesting,
    hasher: any Hashing = SHA256Hasher(),
  ) {
    self.normalizer = normalizer
    self.digester = digester
    self.hasher = hasher
  }

  /// Normalizes the way the policy says and hashes with SHA-256.
  init(policy: FreshnessPolicy) {
    self.init(
      normalizer: ContentNormalizer(policy: policy),
      digester: FingerprintDigester(),
    )
  }

  func reference(of bytes: [UInt8]) -> ContentReference {
    let normalized = normalizer.normalized(bytes)

    return ContentReference(
      byteLength: normalized.count,
      digest: digester.digest(
        of: normalized,
        in: .content,
      ),
    )
  }

  func reference(
    of bytes: [UInt8],
    ranges: [Range<Int>],
  ) throws(FingerprintingError) -> ContentReference {
    var joined: [UInt8] = []

    for range in ranges {
      guard range.lowerBound >= 0, range.upperBound <= bytes.count else {
        throw .regionOutsideFile(range)
      }

      joined.append(contentsOf: bytes[range])
    }

    return reference(of: joined)
  }

  func reference(
    streaming open: () throws(FileContentError) -> any FileChunkReading,
  ) throws(FileContentError) -> StreamedContent {
    let first = try open()
    let analysis = try analysed(first)

    // The file is hashed as it is read the first time, framed with the length it had when it was
    // opened, which is the right frame unless normalization changes it or it changed.
    if !analysis.isNormalized, analysis.length == first.length {
      return StreamedContent(
        reference: ContentReference(
          byteLength: analysis.length,
          digest: analysis.guess.hex(),
        ),
        digest: analysis.digest,
      )
    }

    return try hashedAgain(
      analysis,
      reading: open,
    )
  }

  /// What a first reading of a file finds out.
  private struct Analysis {
    /// The bytes read.
    var length = 0

    /// The SHA-256 of the exact bytes.
    var digest = ""

    /// Whether the file is text that normalization changes.
    var isNormalized = false

    /// The length of the normalized content.
    var normalizedLength = 0

    /// The digest of the content framed as if normalization changed nothing.
    var guess: any DigestAccumulating
  }

  private func analysed(
    _ reader: any FileChunkReading,
  ) throws(FileContentError) -> Analysis {
    var exact = hasher.accumulator()
    var analysis = Analysis(guess: digester.accumulator(in: .content, payloadLength: reader.length))
    var validator = StrictUTF8Validator()
    var run = normalizer.normalizationRun()

    try Self.forEachChunk(of: reader) { chunk in
      exact.add(chunk)
      analysis.guess.add(chunk)
      analysis.length += chunk.count

      if run != nil {
        validator.add(chunk)
        analysis.normalizedLength += run?.normalize(chunk).count ?? 0
      }
    }

    analysis.digest = exact.hex()
    analysis.isNormalized = run != nil && validator.isStrictUTF8
      && analysis.normalizedLength != analysis.length

    return analysis
  }

  /// A second reading, hashing the content with the length the first one found for it.
  private func hashedAgain(
    _ analysis: Analysis,
    reading open: () throws(FileContentError) -> any FileChunkReading,
  ) throws(FileContentError) -> StreamedContent {
    let length = analysis.isNormalized ? analysis.normalizedLength : analysis.length
    var content = digester.accumulator(in: .content, payloadLength: length)
    var exact = hasher.accumulator()
    var run = analysis.isNormalized ? normalizer.normalizationRun() : nil
    var count = 0

    try Self.forEachChunk(of: open()) { chunk in
      exact.add(chunk)
      count += chunk.count
      content.add(run?.normalize(chunk) ?? chunk)
    }

    // What was hashed is the content of the bytes the first reading found only if these are them.
    guard exact.hex() == analysis.digest, count == analysis.length else {
      throw .changedWhileRead
    }

    return StreamedContent(
      reference: ContentReference(
        byteLength: length,
        digest: content.hex(),
      ),
      digest: analysis.digest,
    )
  }

  private static func forEachChunk(
    of reader: any FileChunkReading,
    _ body: ([UInt8]) -> Void,
  ) throws(FileContentError) {
    do {
      while true {
        let chunk = try reader.nextChunk()

        guard !chunk.isEmpty else {
          return
        }

        body(chunk)
      }
    } catch {
      throw FileContentError(reading: error)
    }
  }
}
