import Yams

extension StrictYAMLReader {
  /// Turns a composed node into an authored value, refusing what the design refuses.
  func convert(
    _ node: Node,
    in context: YAMLReadingContext,
    state: inout YAMLConversionState,
  ) throws(YAMLReadingError) -> AuthoredValue {
    let isAlias = try enter(
      node,
      in: context,
      state: &state,
    )
    defer {
      leave(
        node,
        isAlias: isAlias,
        in: context,
        state: &state,
      )
    }

    let contentStart = try checkProperties(
      of: node,
      in: context,
    )

    switch node {
    case let .scalar(scalar):
      return try convert(
        scalar,
        startingAt: contentStart,
        isKey: false,
        isInFlow: state.flowDepth > 0,
        in: context,
      )
    case let .sequence(sequence):
      var items: [AuthoredValue] = []

      for item in sequence {
        try items.append(
          convert(
            item,
            in: context,
            state: &state,
          ),
        )
      }

      return .array(items)
    case let .mapping(mapping):
      return try convert(
        mapping,
        in: context,
        state: &state,
      )
    case let .alias(alias):
      throw .undefinedAlias(context.location(line: alias.mark?.line ?? 1))
    }
  }

  private func convert(
    _ mapping: Node.Mapping,
    in context: YAMLReadingContext,
    state: inout YAMLConversionState,
  ) throws(YAMLReadingError) -> AuthoredValue {
    var members: [AuthoredMember] = []
    var firstLines: [String: Int] = [:]

    for (keyNode, valueNode) in mapping {
      let key = try convertKey(
        keyNode,
        in: context,
        state: &state,
      )

      if let firstLine = firstLines[key] {
        throw .duplicateKey(
          context.location(line: firstLine),
          key: key,
        )
      }

      firstLines[key] = keyNode.mark?.line ?? 1

      try members.append(
        AuthoredMember(
          key: key,
          value: convert(
            valueNode,
            in: context,
            state: &state,
          ),
        ),
      )
    }

    return .object(members)
  }

  private func convertKey(
    _ node: Node,
    in context: YAMLReadingContext,
    state: inout YAMLConversionState,
  ) throws(YAMLReadingError) -> String {
    guard case let .scalar(scalar) = node else {
      throw .unusableKey(context.location(line: node.mark?.line ?? 1))
    }

    let isAlias = try enter(
      node,
      in: context,
      state: &state,
    )
    defer {
      leave(
        node,
        isAlias: isAlias,
        in: context,
        state: &state,
      )
    }

    _ = try convert(
      scalar,
      startingAt: checkProperties(
        of: node,
        in: context,
      ),
      isKey: true,
      isInFlow: state.flowDepth > 0,
      in: context,
    )

    return scalar.string
  }

  private func convert(
    _ scalar: Node.Scalar,
    startingAt contentStart: Int?,
    isKey: Bool,
    isInFlow: Bool,
    in context: YAMLReadingContext,
  ) throws(YAMLReadingError) -> AuthoredValue {
    // The reader drops a byte order mark that starts a text, so it is looked for in the source.
    if let contentStart, context.source.textStartsWithByteOrderMark(at: contentStart) {
      throw .leadingByteOrderMark(context.location(line: context.source.line(at: contentStart)))
    }

    guard scalar.style == .plain else {
      return .string(scalar.string)
    }

    let location = context.location(
      line: contentStart.map(context.source.line(at:)) ?? scalar.mark?.line ?? 1,
    )
    if isInFlow, scalar.string.unicodeScalars.contains("?") {
      throw .unquoted(
        location,
        text: scalar.string,
        problem: .questionMarkInFlow,
      )
    }

    let value = try type(
      scalar.string,
      at: location,
    )

    if isKey, !isText(value) {
      throw .unquoted(
        location,
        text: scalar.string,
        problem: .keyNotText(value),
      )
    }

    if context.kind == .useCase, !scalar.string.isEmpty, let contentStart {
      try checkComment(
        after: scalar.string,
        startingAt: contentStart,
        in: context,
      )
    }

    return value
  }

  private func isText(_ value: AuthoredValue) -> Bool {
    if case .string = value {
      return true
    }

    return false
  }

  private func type(
    _ text: String,
    at location: YAMLLocation,
  ) throws(YAMLReadingError) -> AuthoredValue {
    switch typer.type(of: text) {
    case let .value(value):
      value
    case let .readDifferently(yaml11, yaml12):
      throw .unquoted(
        location,
        text: text,
        problem: .readDifferently(
          yaml11: yaml11,
          yaml12: yaml12,
        ),
      )
    case .integerTooLarge:
      throw .unquoted(
        location,
        text: text,
        problem: .integerTooLarge,
      )
    case .notJSONNumber:
      throw .unquoted(
        location,
        text: text,
        problem: .notJSONNumber,
      )
    }
  }

  private func checkComment(
    after text: String,
    startingAt contentStart: Int,
    in context: YAMLReadingContext,
  ) throws(YAMLReadingError) {
    let finding = commentScanner.finding(
      afterPlainScalar: text,
      startingAt: contentStart,
      in: context.source,
    )

    switch finding {
    case .noComment:
      break
    case let .cutsText(comment):
      throw .textCutByComment(
        context.location(line: comment.line),
        text: text,
        comment: comment.text,
      )
    case .lost:
      throw .malformed(
        context.location(line: context.source.line(at: contentStart)),
        problem: "cannot tell where '\(text)' ends",
      )
    }
  }

  /// Refuses a tag on a node, and returns where the node's own text begins.
  private func checkProperties(
    of node: Node,
    in context: YAMLReadingContext,
  ) throws(YAMLReadingError) -> Int? {
    guard let mark = node.mark,
          let start = context.source.index(
            line: mark.line,
            column: mark.column,
          )
    else {
      return nil
    }

    let properties = context.source.properties(startingAt: start)

    if let tagIndex = properties.tagIndex {
      throw .tagged(context.location(line: context.source.line(at: tagIndex)))
    }

    return properties.contentStart
  }

  /// Counts a node against the limits, and says whether it is an alias being expanded.
  private func enter(
    _ node: Node,
    in context: YAMLReadingContext,
    state: inout YAMLConversionState,
  ) throws(YAMLReadingError) -> Bool {
    var isAlias = false

    if let identity = node.identity {
      isAlias = !state.seen.insert(identity).inserted
    }

    if isAlias, state.aliasDepth == 0 {
      state.expansionLine = state.lastWrittenLine
    }

    if isAlias {
      state.aliasDepth += 1
    }

    state.values += 1

    if state.values > limits.values {
      throw tooManyValues(
        at: node,
        in: context,
        state: state,
      )
    }

    if state.aliasDepth == 0 {
      state.lastWrittenLine = node.mark?.line ?? state.lastWrittenLine
    }

    if isWrittenOnOneLine(node, in: context) {
      state.flowDepth += 1
    }

    if node.isCollection {
      state.depth += 1

      if state.depth > limits.nesting {
        throw .limitExceeded(
          context.location(line: node.mark?.line ?? state.lastWrittenLine),
          .nesting(maximum: limits.nesting),
        )
      }
    }

    return isAlias
  }

  private func tooManyValues(
    at node: Node,
    in context: YAMLReadingContext,
    state: YAMLConversionState,
  ) -> YAMLReadingError {
    if state.aliasDepth > 0 {
      return .limitExceeded(
        context.location(line: state.expansionLine),
        .aliasValues(maximum: limits.values),
      )
    }

    return .limitExceeded(
      context.location(line: node.mark?.line ?? state.lastWrittenLine),
      .values(maximum: limits.values),
    )
  }

  /// Whether the node is a list or mapping in brackets or braces. The composed node does not
  /// remember its style, so the source says: a flow list starts with `[`, a flow mapping with `{`.
  private func isWrittenOnOneLine(
    _ node: Node,
    in context: YAMLReadingContext,
  ) -> Bool {
    guard
      node.isCollection,
      let mark = node.mark,
      let start = context.source.index(
        line: mark.line,
        column: mark.column,
      )
    else {
      return false
    }

    let opener = context.source.properties(startingAt: start).contentStart

    switch node {
    case .sequence:
      return context.source.scalar(at: opener) == "["
    case .mapping:
      return context.source.scalar(at: opener) == "{"
    case .scalar, .alias:
      return false
    }
  }

  private func leave(
    _ node: Node,
    isAlias: Bool,
    in context: YAMLReadingContext,
    state: inout YAMLConversionState,
  ) {
    if node.isCollection {
      state.depth -= 1
    }

    if isWrittenOnOneLine(node, in: context) {
      state.flowDepth -= 1
    }

    if isAlias {
      state.aliasDepth -= 1
    }
  }
}
