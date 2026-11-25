import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterOutputsTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  private func open() throws -> OpenRun {
    try fixture.writer.openVerifyRun(
      StartDraft.sample(selected: ["auth-tests", "style"]),
      in: fixture.workspace,
    )
  }

  private func write(
    _ text: String,
    of validation: String,
    in run: OpenRun,
  ) throws {
    try fixture.writer.writeConsole(
      text,
      of: IdentifierSegment(validating: validation),
      in: run,
    )
  }

  @Test
  func `a console is kept as the validation's console.txt in the run's outputs`() throws {
    let run = try open()
    let folder = ".use-cases/runs/\(run.identifier.text)/outputs"

    try write(
      "1 test failed\n",
      of: "auth-tests",
      in: run,
    )

    #expect(fixture.names(in: folder) == ["auth-tests"])
    #expect(fixture.names(in: "\(folder)/auth-tests") == ["console.txt"])
    #expect(try fixture.read("\(folder)/auth-tests/console.txt") == "1 test failed\n")
  }

  @Test
  func `a console with nothing in it is still a file`() throws {
    let run = try open()

    try write(
      "",
      of: "style",
      in: run,
    )

    #expect(
      fixture.names(in: ".use-cases/runs/\(run.identifier.text)/outputs/style") == ["console.txt"],
    )
  }

  @Test
  func `each validation has a folder of its own`() throws {
    let run = try open()

    try write(
      "a",
      of: "auth-tests",
      in: run,
    )
    try write(
      "b",
      of: "style",
      in: run,
    )

    #expect(
      fixture.names(in: ".use-cases/runs/\(run.identifier.text)/outputs") == [
        "auth-tests",
        "style",
      ],
    )
  }

  @Test
  func `a console is never written over`() throws {
    let run = try open()

    try write(
      "first",
      of: "style",
      in: run,
    )

    #expect(throws: StoreWritingError.self) {
      try write(
        "second",
        of: "style",
        in: run,
      )
    }
    #expect(
      try fixture.read(".use-cases/runs/\(run.identifier.text)/outputs/style/console.txt")
        == "first",
    )
  }

  @Test
  func `a sealed run takes no console`() throws {
    let run = try open()

    _ = try fixture.writer.seal(
      run,
      termination: .interrupted,
    )

    #expect(throws: StoreWritingError.sealed(run.identifier)) {
      try write(
        "late",
        of: "style",
        in: run,
      )
    }
    #expect(fixture.names(in: ".use-cases/runs/\(run.identifier.text)")
      .contains("outputs") == false)
  }

  @Test
  func `the seal digests the console, and the run reads back`() throws {
    let run = try open()

    try write(
      "ok\n",
      of: "auth-tests",
      in: run,
    )
    _ = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    let completion = try fixture.read(".use-cases/runs/\(run.identifier.text)/completion.json")

    #expect(completion.contains("\"auth-tests/console.txt\""))
    #expect(try fixture.readHistory().runs.count == 1)
  }
}
