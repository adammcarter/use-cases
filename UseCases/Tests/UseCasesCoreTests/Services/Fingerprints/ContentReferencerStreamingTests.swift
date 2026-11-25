import Foundation
import Testing
@testable import UseCasesCore

struct ContentReferencerStreamingTests {
  private let hasher = SHA256Hasher()

  private static let policies: [[FreshnessNormalization]] = [
    [],
    [.lineEndings],
    [.whitespace],
    [.lineEndings, .whitespace],
  ]

  private func referencer(_ rules: [FreshnessNormalization]) -> ContentReferencer {
    ContentReferencer(
      policy: FreshnessPolicy(
        bindingIdentity: .content,
        ignoring: rules,
      ),
    )
  }

  /// What reading the bytes as a file does, and how many times the file was opened for it.
  private func streamed(
    _ bytes: [UInt8],
    rules: [FreshnessNormalization],
  ) throws -> (content: StreamedContent, opens: Int) {
    let log = ChunkLog()
    let content = try referencer(rules).reference(
      streaming: { () throws(FileContentError) in
        AccountingChunkReader(
          BufferedChunkReader(bytes: bytes),
          log: log,
        )
      },
    )

    return (content, log.openedCount)
  }

  private func check(
    _ bytes: [UInt8],
    rules: [FreshnessNormalization],
    opens: Int? = nil,
  ) throws {
    let found = try streamed(bytes, rules: rules)

    #expect(found.content.reference == referencer(rules).reference(of: bytes))
    #expect(found.content.digest == hasher.sha256Hex(of: bytes))

    if let opens {
      #expect(found.opens == opens)
    }
  }

  @Test(arguments: policies, ChunkSamples.sizes)
  func `a text file gives the reference of its bytes, read twice only when normalizing changes it`(
    rules: [FreshnessNormalization],
    size: Int,
  ) throws {
    let bytes = ChunkSamples.text(count: size)
    let changed = ContentNormalizer(ignoring: rules).normalized(bytes) != bytes

    try check(
      bytes,
      rules: rules,
      opens: changed ? 2 : 1,
    )
  }

  @Test(arguments: policies, ChunkSamples.sizes)
  func `a file that is not text gives the reference of its bytes, at every size`(
    rules: [FreshnessNormalization],
    size: Int,
  ) throws {
    try check(
      ChunkSamples.bytes(count: size) + [0xFF],
      rules: rules,
      opens: 1,
    )
  }

  @Test(arguments: policies, ChunkSamples.sizes)
  func `a file of text that normalization changes gives the reference of its normalized bytes`(
    rules: [FreshnessNormalization],
    size: Int,
  ) throws {
    let bytes = ChunkSamples.text(count: size, lineEnding: "\r\n")
    let changed = ContentNormalizer(ignoring: rules).normalized(bytes) != bytes

    try check(
      bytes,
      rules: rules,
      opens: changed ? 2 : 1,
    )
  }

  @Test
  func `a line ending cut by the end of a chunk is one line ending`() throws {
    var bytes = ChunkSamples.text(count: 65535)
    bytes.append(contentsOf: Array("\r\nmore\r\n".utf8))

    try check(
      bytes,
      rules: [.lineEndings],
      opens: 2,
    )
  }

  @Test
  func `a character cut by the end of a chunk is one character`() throws {
    var bytes = ChunkSamples.text(count: 65535)
    bytes.append(contentsOf: Array("€ and\r\nmore".utf8))

    try check(
      bytes,
      rules: [.lineEndings],
      opens: 2,
    )
  }

  @Test
  func `a file that grew while it was read is still the reference of the bytes that were read`()
    throws
  {
    let bytes = ChunkSamples.text(count: 100)
    let content = try referencer([]).reference(
      streaming: { () throws(FileContentError) in
        ScriptedChunkReader(
          chunks: [bytes],
          length: 40,
        )
      },
    )

    #expect(content.reference == referencer([]).reference(of: bytes))
    #expect(content.digest == hasher.sha256Hex(of: bytes))
  }

  @Test
  func `a file that is not the same on the second reading changed while it was read`() {
    let first = Array("one\r\ntwo".utf8)
    let second = Array("one\r\nTWO".utf8)
    let opens = ChunkLog()

    #expect(throws: FileContentError.changedWhileRead) {
      try referencer([.lineEndings]).reference(
        streaming: { () throws(FileContentError) in
          opens.open()

          return BufferedChunkReader(bytes: opens.openedCount == 1 ? first : second)
        },
      )
    }
  }

  @Test
  func `a file that is longer on the second reading changed while it was read`() {
    let opens = ChunkLog()

    #expect(throws: FileContentError.changedWhileRead) {
      try referencer([.lineEndings]).reference(
        streaming: { () throws(FileContentError) in
          opens.open()

          return BufferedChunkReader(
            bytes: Array((opens.openedCount == 1 ? "a\r\n" : "a\r\nb").utf8),
          )
        },
      )
    }
  }

  @Test
  func `a file that cannot be opened is the failure of the opening`() {
    #expect(throws: FileContentError.missing) {
      try referencer([]).reference(
        streaming: { () throws(FileContentError) in
          throw .missing
        },
      )
    }
  }

  @Test
  func `a file that goes while it is read is missing, and one the system refuses is unreadable`()
    throws
  {
    let gone = URL(fileURLWithPath: "/gone")
    let refused = FileSystemError.unreadable(gone, reason: "input/output error")

    #expect(throws: FileContentError.missing) {
      try referencer([]).reference(
        streaming: { () throws(FileContentError) in
          ScriptedChunkReader(chunks: [[1]], failure: .notFound(gone))
        },
      )
    }
    #expect(throws: FileContentError.unreadable(refused)) {
      try referencer([]).reference(
        streaming: { () throws(FileContentError) in
          ScriptedChunkReader(chunks: [[1]], failure: refused)
        },
      )
    }
  }

  @Test
  func `no chunk handed to the digest is bigger than a chunk`() throws {
    let log = ChunkLog()

    _ = try referencer([.lineEndings]).reference(
      streaming: { () throws(FileContentError) in
        AccountingChunkReader(
          BufferedChunkReader(bytes: ChunkSamples.text(count: 500_000, lineEnding: "\r\n")),
          log: log,
        )
      },
    )

    #expect(log.largestChunk <= 65536)
    #expect(log.openedCount == 2)
    #expect(log.streamedBytes == 1_000_000)
  }
}
