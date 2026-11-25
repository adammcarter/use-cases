import Foundation
import Testing
@testable import UseCasesCore

/// Chapter 09 §14: every YAML implementation reads an accepted file one way. These hold what the
/// writer writes to readers that are not libyaml: PyYAML and ruamel.yaml (run by `uv`), Ruby's
/// Psych and go-yaml.
struct OtherYAMLReadersTests {
  private struct Case {
    let yaml: String
    let json: String
  }

  private let emitter = YAMLEmitter()
  private let serialiser = UseCaseSerialiser()

  /// Every text of the corpus in each place a writer puts one: after a key, in a list on one
  /// line, in a list of its own, inside a mapping, in a list of mappings, and as a key.
  private func textCases() -> [Case] {
    var generator = SeededGenerator(seed: 4557)
    let texts = NastyText.fixed + (0 ..< 600).map { _ in
      NastyText.text(using: &generator)
    }

    return texts.flatMap { text -> [Case] in
      [
        StoreJSONValue.members(["k": .string(text)]),
        .members(["k": .strings([text, "x"])]),
        .members(["k": .strings([text])]),
        .members(["k": .members(["a": .string(text)])]),
        .members(["k": .array([.members(["a": .string(text), "b": .integer(1)])])]),
        .members([text: .integer(1)]),
      ].map(written)
    }
  }

  /// The use cases of the property test, as the lines `save` puts in a definition file.
  private func useCaseCases() throws -> [Case] {
    try (0 ..< 400).map { seed in
      var generator = UseCaseGenerator(seed: seed)
      let definition = try generator.definition()
      let local = definition.localIdentifier.text
      let item = serialiser.itemLines(
        of: definition,
        writing: local,
        indent: 2,
      )

      return Case(
        yaml: (["use_cases:"] + item).joined(separator: "\n") + "\n",
        json: StoreJSONWriter().compact(
          .members(["use_cases": .array([definition.document(writing: local)])]),
        ).utf8Text,
      )
    }
  }

  private func written(_ value: StoreJSONValue) -> Case {
    Case(
      yaml: emitter.lines(of: value).joined(separator: "\n") + "\n",
      json: StoreJSONWriter().compact(value).utf8Text,
    )
  }

  private func differences(
    of reader: OtherYAMLReader,
    reading cases: [Case],
  ) async throws -> String {
    let command = try #require(reader.command)
    let fixture = try ProcessFixture()
    let file = try JSONSerialization.data(
      withJSONObject: cases.map { found in
        ["yaml": found.yaml, "json": found.json]
      },
    )
    try fixture.directory.write("cases.json", bytes: Array(file))

    for (name, text) in reader.files {
      try fixture.directory.write(name, text)
    }

    let run = try await fixture.supervisor().run(
      fixture.request(
        command,
        timeout: .seconds(300),
      ),
    )

    return run.console.text
  }

  private func expectEveryText(read reader: OtherYAMLReader) async throws {
    let cases = textCases()

    let output = try await differences(of: reader, reading: cases)

    #expect(output == "OK \(cases.count)\n", Comment(rawValue: output))
  }

  private func expectEveryUseCase(read reader: OtherYAMLReader) async throws {
    let cases = try useCaseCases()

    let output = try await differences(of: reader, reading: cases)

    #expect(output == "OK \(cases.count)\n", Comment(rawValue: output))
  }

  static let noUV: Comment = "uv is not installed, so PyYAML and ruamel.yaml cannot be run"
  static let noGo: Comment = "go is not installed, so go-yaml cannot be run"
  static let noRuby: Comment = "ruby is not installed, so Psych cannot be run"

  @Test(
    .enabled(if: InstalledTool.uvProgram != nil, OtherYAMLReadersTests.noUV),
    arguments: OtherYAMLReader.usingUV,
  )
  func `pyyaml and ruamel read a text as itself wherever it is written`(
    reader: OtherYAMLReader,
  ) async throws {
    try await expectEveryText(read: reader)
  }

  @Test(
    .enabled(if: InstalledTool.uvProgram != nil, OtherYAMLReadersTests.noUV),
    arguments: OtherYAMLReader.usingUV,
  )
  func `pyyaml and ruamel read a use case written as a definition file as itself`(
    reader: OtherYAMLReader,
  ) async throws {
    try await expectEveryUseCase(read: reader)
  }

  @Test(
    .enabled(if: InstalledTool.goProgram != nil, OtherYAMLReadersTests.noGo),
    arguments: OtherYAMLReader.usingGo,
  )
  func `go-yaml reads a text as itself wherever it is written`(
    reader: OtherYAMLReader,
  ) async throws {
    try await expectEveryText(read: reader)
  }

  @Test(
    .enabled(if: InstalledTool.goProgram != nil, OtherYAMLReadersTests.noGo),
    arguments: OtherYAMLReader.usingGo,
  )
  func `go-yaml reads a use case written as a definition file as itself`(
    reader: OtherYAMLReader,
  ) async throws {
    try await expectEveryUseCase(read: reader)
  }

  @Test(.enabled(if: InstalledTool.rubyProgram != nil, OtherYAMLReadersTests.noRuby))
  func `psych reads a text as itself wherever it is written`() async throws {
    try await expectEveryText(read: .psych)
  }

  @Test(.enabled(if: InstalledTool.rubyProgram != nil, OtherYAMLReadersTests.noRuby))
  func `psych reads a use case written as a definition file as itself`() async throws {
    try await expectEveryUseCase(read: .psych)
  }
}
