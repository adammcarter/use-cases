import Testing
@testable import UseCasesCLI

struct CommandResultCancelledTests {
  @Test
  func `a cancelled request is exit 130 with one line on stderr and nothing on stdout`() {
    let result = CommandResult.cancelled(
      command: "status",
      json: false,
    )

    #expect(result.exitCode == 130)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == "use-cases status: cancelled\n")
  }

  @Test
  func `under json it is also the one document, an error of kind cancelled`() throws {
    let result = CommandResult.cancelled(
      command: "status",
      json: true,
      message: "cancelled; the write had begun",
    )
    let document = try result.document()

    #expect(result.exitCode == 130)
    #expect(result.standardError == "use-cases status: cancelled; the write had begun\n")
    #expect(document["output_version"] == .integer(1))
    #expect(document["command"] == .string("status"))
    #expect(document["error"]?["kind"] == .string("cancelled"))
    #expect(document["error"]?["message"] == .string("cancelled; the write had begun"))
  }

  @Test
  func `the document follows the published schema`() throws {
    let document = try CommandResult.cancelled(
      command: "verify",
      json: true,
    ).document()

    #expect(try PublishedSchema(path: "schemas/output/cli-error.schema.json")
      .failures(of: document) == [])
  }
}
