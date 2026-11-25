/// Writes ``StoreJSONValue`` as the YAML a person would write, in the order given.
struct YAMLEmitter: YAMLEmitting {
  private let scalars: any YAMLScalarWriting
  private let literals: any YAMLLiteralBlockWriting
  private let layout: YAMLLayout

  init(
    scalars: any YAMLScalarWriting = YAMLScalarWriter(),
    literals: any YAMLLiteralBlockWriting = YAMLLiteralBlockWriter(),
    layout: YAMLLayout = .useCaseFile,
  ) {
    self.scalars = scalars
    self.literals = literals
    self.layout = layout
  }

  func lines(of value: StoreJSONValue) -> [String] {
    switch value {
    case let .object(members) where !members.isEmpty:
      mappingLines(
        members,
        indent: 0,
      )
    case let .array(items) where !items.isEmpty:
      listLines(
        items,
        indent: 0,
      )
    default:
      [blockValue(value)]
    }
  }

  /// One member per line, a collection under its key unless it fits on the key's line.
  private func mappingLines(
    _ members: [StoreJSONMember],
    indent: Int,
  ) -> [String] {
    var lines: [String] = []

    for member in members {
      let head = padding(indent) + scalars.text(
        of: member.key,
        in: .block,
      ) + ":"

      switch member.value {
      case let .object(inner) where !inner.isEmpty:
        lines += collection(
          head: head,
          value: member.value,
          nested: mappingLines(
            inner,
            indent: indent + 2,
          ),
        )
      case let .array(items) where !items.isEmpty:
        lines += collection(
          head: head,
          value: member.value,
          nested: listLines(
            items,
            indent: indent + 2,
          ),
        )
      default:
        lines += scalarLines(
          head: head,
          value: member.value,
          indent: indent,
        )
      }
    }

    return lines
  }

  private func listLines(
    _ items: [StoreJSONValue],
    indent: Int,
  ) -> [String] {
    var lines: [String] = []

    for item in items {
      let marker = padding(indent) + "-"

      switch item {
      case let .object(members) where !members.isEmpty:
        // The first member shares the line with the dash; the others line up under it.
        var inner = mappingLines(
          members,
          indent: indent + 2,
        )
        lines.append(marker + " " + inner.removeFirst().dropFirst(indent + 2))
        lines += inner
      case let .array(inner) where !inner.isEmpty:
        lines += collection(
          head: marker,
          value: item,
          nested: listLines(
            inner,
            indent: indent + 2,
          ),
        )
      default:
        lines += scalarLines(
          head: marker,
          value: item,
          indent: indent,
        )
      }
    }

    return lines
  }

  /// A scalar after its head, or under it as a literal block when it is text of several lines
  /// that a block holds exactly.
  private func scalarLines(
    head: String,
    value: StoreJSONValue,
    indent: Int,
  ) -> [String] {
    if case let .string(text) = value,
       let block = literals.block(
         of: text,
         parentIndent: indent,
       )
    {
      return [head + " " + block.header] + block.lines
    }

    return [head + " " + blockValue(value)]
  }

  /// A collection on the line of its head when it is all plain values and the line fits, and
  /// under it otherwise.
  private func collection(
    head: String,
    value: StoreJSONValue,
    nested: @autoclosure () -> [String],
  ) -> [String] {
    if value.holdsOnlyPlainValues {
      let line = head + " " + oneLine(value)

      if layout.fits(line) {
        return [line]
      }
    }

    return [head] + nested()
  }

  /// A scalar written after a key or a dash, or an empty list or mapping.
  private func blockValue(_ value: StoreJSONValue) -> String {
    guard case let .string(text) = value else {
      return oneLine(value)
    }

    return scalars.text(
      of: text,
      in: .block,
    )
  }

  /// A scalar, or a list or mapping of scalars, on one line.
  private func oneLine(_ value: StoreJSONValue) -> String {
    switch value {
    case let .array(items):
      "[" + items.map(flowItem).joined(separator: ", ") + "]"
    case let .object(members) where members.isEmpty:
      "{}"
    case let .object(members):
      flowMapping(members)
    default:
      flowItem(value)
    }
  }

  private func flowMapping(_ members: [StoreJSONMember]) -> String {
    let inner = members.map(flowMember).joined(separator: ", ")

    return "{ " + inner + " }"
  }

  private func flowMember(_ member: StoreJSONMember) -> String {
    scalars.text(
      of: member.key,
      in: .flow,
    ) + ": " + flowItem(member.value)
  }

  /// A scalar as an item of a list or mapping on one line.
  private func flowItem(_ value: StoreJSONValue) -> String {
    switch value {
    case .null:
      "null"
    case let .boolean(flag):
      flag ? "true" : "false"
    case let .integer(number):
      String(number)
    case let .number(number):
      number.isFinite ? String(number) : "null"
    case let .string(text):
      scalars.text(
        of: text,
        in: .flow,
      )
    case .array, .object:
      oneLine(value)
    }
  }

  private func padding(_ width: Int) -> String {
    String(repeating: " ", count: width)
  }
}

private extension StoreJSONValue {
  /// A list or mapping whose members are all scalars.
  var holdsOnlyPlainValues: Bool {
    switch self {
    case let .array(items):
      items.allSatisfy(\.fitsOnALine)
    case let .object(members):
      members.allSatisfy { member in
        member.value.fitsOnALine
      }
    default:
      false
    }
  }

  /// A scalar that is not text of several lines, which is written as a block of its own.
  var fitsOnALine: Bool {
    switch self {
    case .array, .object:
      false
    case let .string(text):
      !text.unicodeScalars.contains("\n")
    default:
      true
    }
  }
}
