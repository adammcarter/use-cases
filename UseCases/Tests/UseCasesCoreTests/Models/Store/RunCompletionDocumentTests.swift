import Testing
@testable import UseCasesCore

struct RunCompletionDocumentTests {
  private func completion(startDigest: String?) -> RunCompletion {
    RunCompletion(
      version: 1,
      identifier: .sample(42),
      resultCount: 1,
      manifestDigest: StoreSamples.digest("1"),
      resultsDigest: StoreSamples.digest("2"),
      details: RunCompletion.Details(
        finishedAt: StoreSamples.timestamp,
        termination: .interrupted,
        outputDigests: [
          FileDigest(path: "auth-tests/console.txt", digest: StoreSamples.digest("3")),
        ],
        reportDigests: [
          FileDigest(path: "auth-tests/auth-tests.jsonl", digest: StoreSamples.digest("4")),
          FileDigest(path: "auth-tests/second report.xml", digest: StoreSamples.digest("5")),
        ],
        startDigest: startDigest,
      ),
    )
  }

  @Test(arguments: [StoreSamples.digest("6"), nil])
  func `a marker passes the completion schema`(startDigest: String?) throws {
    let document = try WrittenDocument(
      #require(completion(startDigest: startDigest).document),
      schema: .completion,
    )

    #expect(document.failures.isEmpty)
    #expect(try document.object.contains("start_sha256") == (startDigest != nil))
  }

  @Test(arguments: [StoreSamples.digest("6"), nil])
  func `the reader reads back exactly the marker that was written`(startDigest: String?) throws {
    let written = completion(startDigest: startDigest)
    let document = try WrittenDocument(
      #require(written.document),
      schema: .completion,
    )

    #expect(try RunCompletion(authored: document.object) == written)
  }

  @Test
  func `a marker with no digest maps still has both maps`() throws {
    let empty = RunCompletion(
      version: 1,
      identifier: .sample(42),
      resultCount: 0,
      manifestDigest: StoreSamples.digest("1"),
      resultsDigest: StoreSamples.digest("2"),
      details: RunCompletion.Details(
        finishedAt: StoreSamples.timestamp,
        termination: .completed,
        outputDigests: [],
        reportDigests: [],
        startDigest: nil,
      ),
    )
    let document = try WrittenDocument(
      #require(empty.document),
      schema: .completion,
    )

    #expect(document.failures.isEmpty)
    #expect(try document.object.contains("outputs_sha256"))
    #expect(try document.object.contains("reports_sha256"))
  }

  @Test
  func `a marker of a newer version has only its envelope and cannot be written`() {
    let envelope = RunCompletion(
      version: 2,
      identifier: .sample(42),
      resultCount: 1,
      manifestDigest: StoreSamples.digest("1"),
      resultsDigest: StoreSamples.digest("2"),
      details: nil,
    )

    #expect(envelope.document == nil)
  }
}
