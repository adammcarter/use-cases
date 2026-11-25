/// Lays a use case out as ``YAMLLayout/useCaseFile`` says.
struct UseCaseSerialiser: UseCaseSerialising {
  private let emitter: any YAMLEmitting

  init(emitter: any YAMLEmitting = YAMLEmitter(layout: .useCaseFile)) {
    self.emitter = emitter
  }

  func lines(
    of definition: UseCaseDefinition,
    writing id: String,
  ) -> [String] {
    emitter.lines(of: definition.document(writing: id))
  }

  func itemLines(
    of definition: UseCaseDefinition,
    writing id: String,
    indent: Int,
  ) -> [String] {
    let margin = String(repeating: " ", count: indent)

    return lines(
      of: definition,
      writing: id,
    ).enumerated().map { index, line in
      if line.isEmpty {
        return line
      }

      return margin + (index == 0 ? "- " : "  ") + line
    }
  }
}
