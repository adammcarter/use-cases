import Testing
@testable import UseCasesCore

struct VerifiedRunTests {
  private func result(
    _ route: String,
    _ verdict: Verdict,
  ) throws -> StoredResult {
    try StoredResult(
      useCase: .sample("app.toggle"),
      route: .sample(route),
      fingerprint: .sample("a"),
      verdict: verdict,
      detail: StoredResultDetail(
        recordedAt: StoreSamples.timestamp,
        origin: .validations(
          [IdentifierSegment(validating: "unit-tests")],
          links: [LinkResult(key: StoreSamples.linkKey, verdict: verdict)],
        ),
        message: nil,
        attachments: [],
      ),
    )
  }

  private func manifest(errors: [String] = []) -> RunManifest {
    RunManifest(
      identifier: .sample(42),
      createdAt: StoreSamples.timestamp,
      kind: .verify,
      sources: [],
      errors: errors,
      diagnostics: [],
      unlinkedTests: [],
      notes: ["a note"],
    )
  }

  @Test
  func `the verdicts are counted by status, from pass to error, leaving out the empty ones`(
  ) throws {
    let run = try VerifiedRun(
      manifest: manifest(),
      results: [
        result("a", .fail),
        result("b", .pass),
        result("c", .pass),
        result("d", .error),
      ],
      isCancelled: false,
    )

    #expect(run.verdictCount == 4)
    #expect(run.verdictCounts.map(\.status) == ["pass", "fail", "error"])
    #expect(run.verdictCounts.map(\.count) == [2, 1, 1])
  }

  @Test
  func `a run has run errors when its manifest does, and a failed test is not one`() throws {
    let failing = try VerifiedRun(
      manifest: manifest(),
      results: [result("a", .fail)],
      isCancelled: false,
    )
    let broken = VerifiedRun(
      manifest: manifest(errors: ["unit-tests: no report"]),
      results: [],
      isCancelled: false,
    )

    #expect(!failing.hasRunErrors)
    #expect(broken.hasRunErrors)
    #expect(broken.errors == ["unit-tests: no report"])
  }

  @Test
  func `a request that read nothing has the notes it was given and no run`() {
    let run = VerifiedRun(nothingToReadNotes: ["nothing to read"])

    #expect(run.runIdentifier == nil)
    #expect(run.notes == ["nothing to read"])
    #expect(!run.hasRunErrors)
    #expect(run.verdictCounts.isEmpty)
  }

  @Test
  func `the document of a sealed run is its manifest fields and its results`() throws {
    let run = try VerifiedRun(
      manifest: manifest(),
      results: [result("a", .pass)],
      isCancelled: false,
    )

    let value = try JSONReader().read(run.documentText(step: "finish", outputVersion: 1))
    let object = try AuthoredObject(value, at: "")

    #expect(try object.requiredString("command") == "verify")
    #expect(try object.requiredString("step") == "finish")
    #expect(try object.requiredString("kind") == "verify")
    #expect(try object.requiredString("run_id") == RunIdentifier.sample(42).text)
    #expect(try object.objects("results").count == 1)
    #expect(!object.contains("cancelled"))
  }

  @Test
  func `a cancelled run says so in its document`() throws {
    let run = VerifiedRun(
      manifest: manifest(),
      results: [],
      isCancelled: true,
    )

    let object = try AuthoredObject(
      JSONReader().read(run.documentText(step: "finish", outputVersion: 1)),
      at: "",
    )

    #expect(try object.optionalBoolean("cancelled") == true)
  }

  @Test
  func `the document of a request that read nothing has no run in it`() throws {
    let run = VerifiedRun(nothingToReadNotes: ["nothing to read"])

    let object = try AuthoredObject(
      JSONReader().read(run.documentText(step: "finish", outputVersion: 1)),
      at: "",
    )

    #expect(!object.contains("run_id"))
    #expect(try object.strings("notes") == ["nothing to read"])
    #expect(try object.objects("results").isEmpty)
    #expect(try object.strings("errors").isEmpty)
  }
}
