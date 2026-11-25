import Testing
@testable import UseCasesCore

struct UseCaseSerialiserRoundTripTests {
  private let serialiser = UseCaseSerialiser()
  private let reader = StrictYAMLReader()

  /// The text exactly as it is, for comparing what Swift's `==` on strings would call equal.
  private func bytes(_ document: StoreJSONValue) -> [UInt8] {
    StoreJSONWriter().compact(document)
  }

  @Test(arguments: 0 ..< 400)
  func `a use case written as a definition file's item reads back as the same use case`(
    seed: Int,
  ) throws {
    var generator = UseCaseGenerator(seed: seed)
    let definition = try generator.definition()
    let text = (["use_cases:"] + serialiser.itemLines(
      of: definition,
      writing: definition.localIdentifier.text,
      indent: 2,
    )).joined(separator: "\n") + "\n"

    let value = try reader.read(
      text,
      file: "use-cases/a.yml",
      kind: .useCase,
    )
    let root = try AuthoredObject(
      value,
      at: "",
    )
    let item = try #require(root.objects("use_cases").first)
    let read = try UseCaseDefinition(authored: item)

    #expect(read == definition)
    #expect(
      bytes(read.document(writing: "x")) == bytes(definition.document(writing: "x")),
      "seed \(seed) is not the same to the byte:\n\(text)",
    )
  }

  @Test(arguments: 0 ..< 400)
  func `a use case printed with its full id reads back as the document it was made from`(
    seed: Int,
  ) throws {
    var generator = UseCaseGenerator(seed: seed)
    let definition = try generator.definition()
    let id = "app.group.\(definition.localIdentifier.text)"
    let text = serialiser.lines(
      of: definition,
      writing: id,
    ).joined(separator: "\n") + "\n"

    let value = try reader.read(
      text,
      file: "show",
      kind: .useCase,
    )

    #expect(
      bytes(StoreJSONValue(value)) == bytes(definition.document(writing: id)),
      "seed \(seed) is not the same to the byte:\n\(text)",
    )
  }

  @Test(arguments: 0 ..< 400)
  func `the same use case as JSON reads back as the document it was made from`(
    seed: Int,
  ) throws {
    var generator = UseCaseGenerator(seed: seed)
    let definition = try generator.definition()
    let document = definition.document(writing: "app.group.x")
    let json = StoreJSONWriter().pretty(document).utf8Text

    let value = try JSONReader().read(json)

    #expect(
      bytes(StoreJSONValue(value)) == bytes(document),
      "seed \(seed) is not the same to the byte:\n\(json)",
    )
  }

  @Test(arguments: 0 ..< 100)
  func `the same use case written twice is the same text`(seed: Int) throws {
    var generator = UseCaseGenerator(seed: seed)
    let definition = try generator.definition()

    #expect(
      serialiser.lines(of: definition, writing: "a") ==
        serialiser.lines(of: definition, writing: "a"),
    )
  }
}
