import Testing
@testable import UseCasesCore

struct StoredResultDocumentTests {
  private func result(
    origin: ResultOrigin = .recorded,
    message: String? = "checked by hand",
    attachments: [ResultAttachment] = [],
  ) -> StoredResult {
    StoredResult(
      useCase: .sample(StoreSamples.useCase),
      route: .sample(StoreSamples.route),
      fingerprint: .sample("a"),
      verdict: .fail,
      detail: StoredResultDetail(
        recordedAt: StoreSamples.timestamp,
        origin: origin,
        message: message,
        attachments: attachments,
      ),
    )
  }

  private func validations() throws -> ResultOrigin {
    try .validations(
      [IdentifierSegment(validating: "auth-tests")],
      links: [
        // In the order of the keys, which is the order the writer prints them in.
        LinkResult(key: StoreSamples.otherLinkKey, verdict: nil),
        LinkResult(key: StoreSamples.linkKey, verdict: .fail),
      ],
    )
  }

  private func screenshot() -> ResultAttachment {
    ResultAttachment(
      name: "screen shot.png",
      digest: StoreSamples.digest("c"),
      sizeBytes: 15,
      mediaType: "image/png",
    )
  }

  private func schemaFailures(_ result: StoredResult) throws -> [SchemaFailure] {
    let document = try #require(result.document)

    return try WrittenDocument(
      document,
      schema: .result,
    ).failures
  }

  @Test
  func `a recorded verdict passes the result schema and has no links`() throws {
    let recorded = result()

    #expect(try schemaFailures(recorded).isEmpty)
    #expect(
      recorded.document == .members([
        "record_version": .integer(1),
        "use_case": .string(StoreSamples.useCase),
        "route": .string(StoreSamples.route),
        "fingerprint": .string(RouteFingerprint.sample("a").text),
        "status": .string("fail"),
        "via": .strings(["record"]),
        "recorded_at": .string(StoreSamples.timestamp),
        "message": .string("checked by hand"),
      ]),
    )
  }

  @Test
  func `a verdict from reports passes the result schema with every link, a null one included`(
  ) throws {
    let judged = try result(origin: validations())

    #expect(try schemaFailures(judged).isEmpty)
  }

  @Test
  func `a verdict with attachments passes the result schema`() throws {
    let attached = result(attachments: [screenshot()])

    #expect(try schemaFailures(attached).isEmpty)
  }

  @Test
  func `a verdict with no message and no attachments has neither field`() throws {
    let plain = result(message: nil)
    let document = try WrittenDocument(
      #require(plain.document),
      schema: .result,
    )

    #expect(document.failures.isEmpty)
    #expect(try !document.object.contains("message"))
    #expect(try !document.object.contains("attachments"))
  }

  @Test(arguments: [true, false])
  func `the reader reads back exactly the result that was written`(withAttachment: Bool) throws {
    let written = try result(
      origin: withAttachment ? .recorded : validations(),
      attachments: withAttachment ? [screenshot()] : [],
    )
    let document = try WrittenDocument(
      #require(written.document),
      schema: .result,
    )

    #expect(try StoredResult(authored: document.object) == written)
  }

  @Test
  func `a result of a newer version has only its envelope and cannot be written`() {
    let envelope = StoredResult(
      useCase: .sample(StoreSamples.useCase),
      route: .sample(StoreSamples.route),
      fingerprint: .sample("a"),
      verdict: .pass,
      detail: nil,
    )

    #expect(envelope.document == nil)
  }
}
