import Testing
@testable import UseCasesCore

struct StartStampDocumentTests {
  private func stamp(openedBy: RunOpener = .start) throws -> StartStamp {
    let draft = try StartDraft.sample(openedBy: openedBy)

    return StartStamp(
      identifier: .sample(42),
      startedAt: StoreSamples.timestamp,
      openedBy: draft.openedBy,
      selected: draft.selected,
      validationsDigest: draft.validationsDigest,
      routes: draft.routes,
      files: draft.files,
    )
  }

  @Test(arguments: [RunOpener.start, .run])
  func `the document follows the start schema`(openedBy: RunOpener) throws {
    let written = try WrittenDocument(
      stamp(openedBy: openedBy).document,
      schema: .start,
    )

    #expect(written.failures.isEmpty)
  }

  @Test(arguments: [RunOpener.start, .run])
  func `a stamp reads back as it was written`(openedBy: RunOpener) throws {
    let original = try stamp(openedBy: openedBy)
    let written = try WrittenDocument(
      original.document,
      schema: .start,
    )

    #expect(try StartStamp(authored: written.object) == original)
  }

  @Test
  func `the files are an object keyed by path`() throws {
    let written = try WrittenDocument(
      stamp().document,
      schema: .start,
    )
    let files = try written.object.requiredObject("files")

    #expect(files.members.map(\.key) == ["Tests/AuthTests/LoginTests.swift"])
  }

  @Test
  func `a stamp that names an unknown opener is not read`() throws {
    let written = try WrittenDocument(
      stamp().document,
      schema: .start,
    )
    var members = try written.object.members
    members.removeAll { $0.key == "opened_by" }
    members.append(AuthoredMember(key: "opened_by", value: .string("someone")))

    #expect(throws: AuthoredShapeError.self) {
      try StartStamp(authored: AuthoredObject(.object(members), at: ""))
    }
  }
}
