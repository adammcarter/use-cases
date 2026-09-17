/// Writes a use-case document as YAML, byte for byte as the TypeScript's
/// `stringify(document, { lineWidth: 0 })` from the `yaml` package (2.9.0)
/// writes it.
///
/// Yams cannot do this: libyaml always writes a sequence nested in a mapping
/// flush with its key (`key:\n- item`, emitter.c's indentless sequence), while
/// `yaml` indents it (`key:\n  - item`), and no `Emitter.Options` changes that.
/// The committed `use-cases/*.yml` files are what `yaml` writes, so a mutation
/// written any other way would rewrite every line of a user's matrix.
///
/// The document the TypeScript hands `stringify` is plain JSON data — the file
/// was read through `toJSON()` — so there are no comments, anchors, tags or
/// source styles to carry, and every collection is written in block style. The
/// port is of exactly that subset: `stringifyDocument`, `stringifyCollection`,
/// `stringifyPair`, `stringifyNumber` and `stringifyString`, with folding off
/// (`lineWidth: 0`). Every length and pattern is measured in UTF-16 code units,
/// as JavaScript measures it.
enum UseCaseFileEmitter {
  /// The whole document, ending in one newline.
  static func stringify(_ document: JSONObject) -> String {
    let body = value(.object(document), Context(indent: [], isImplicitKey: false))
    return CodeUnits.string(body + [CodeUnits.lineFeed])
  }

  struct Context {
    /// The indentation continuation lines of this node start with.
    var indent: [UInt16]

    /// True while writing a mapping key.
    var isImplicitKey: Bool
  }

  static let indentStep: [UInt16] = [CodeUnits.space, CodeUnits.space]

  // MARK: - Nodes

  private static func value(
    _ node: JSONValue,
    _ context: Context,
  ) -> [UInt16] {
    switch node {
    case .null:
      Array("null".utf16)
    case let .bool(flag):
      Array((flag ? "true" : "false").utf16)
    case let .number(number):
      Array(numberText(number).utf16)
    case let .string(text):
      string(Array(text.utf16), context)
    case let .array(items):
      collection(
        items.map { item in
          { itemContext in
            value(item, itemContext)
          }
        },
        prefix: [CodeUnits.hyphenMinus, CodeUnits.space],
        empty: [CodeUnits.leftSquareBracket, CodeUnits.rightSquareBracket],
        itemIndent: context.indent + indentStep,
        context,
      )
    case let .object(object):
      collection(
        javaScriptOrder(object).map { member in
          { itemContext in
            pair(member.key, member.value, itemContext)
          }
        },
        prefix: [],
        empty: [CodeUnits.leftCurlyBracket, CodeUnits.rightCurlyBracket],
        itemIndent: context.indent,
        context,
      )
    }
  }

  /// `stringifyBlockCollection`: one line per item, continuation lines at the
  /// collection's own indent; `[]` or `{}` when there are no items.
  private static func collection(
    _ items: [(Context) -> [UInt16]],
    prefix: [UInt16],
    empty: [UInt16],
    itemIndent: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    guard !items.isEmpty else {
      return empty
    }
    let itemContext = Context(indent: itemIndent, isImplicitKey: context.isImplicitKey)
    var text: [UInt16] = []
    for (index, item) in items.enumerated() {
      if index > 0 {
        text += [CodeUnits.lineFeed] + context.indent
      }
      text += prefix + item(itemContext)
    }
    return text
  }

  /// `stringifyPair` for a string key. A key longer than 1024 code units
  /// becomes an explicit `? key` / `: value` pair.
  private static func pair(
    _ key: String,
    _ member: JSONValue,
    _ context: Context,
  ) -> [UInt16] {
    var pairContext = Context(indent: context.indent + indentStep, isImplicitKey: true)
    let keyText = string(Array(key.utf16), pairContext)
    let isExplicitKey = keyText.count > 1024
    var text = isExplicitKey
      ? [CodeUnits.questionMark, CodeUnits.space] + keyText + [CodeUnits.lineFeed] + context
      .indent + [CodeUnits.colon]
      : keyText + [CodeUnits.colon]
    pairContext.isImplicitKey = false
    let valueText = value(member, pairContext)
    var separator: [UInt16] = [CodeUnits.space]
    switch member {
    case let .array(items) where !isExplicitKey:
      if !items.isEmpty {
        separator = [CodeUnits.lineFeed] + pairContext.indent
      }
    case let .object(object) where !isExplicitKey:
      if !object.isEmpty {
        separator = [CodeUnits.lineFeed] + pairContext.indent
      }
    default:
      break
    }
    text += separator + valueText
    return text
  }

  /// The object's members in `Object.keys` order: array-index keys first, in
  /// ascending numeric order, then every other key in insertion order.
  private static func javaScriptOrder(_ object: JSONObject) -> [(key: String, value: JSONValue)] {
    let members = object.pairs
    var indexed: [(index: UInt64, member: (key: String, value: JSONValue))] = []
    var named: [(key: String, value: JSONValue)] = []
    for member in members {
      if let index = arrayIndex(member.key) {
        indexed.append((index, member))
      } else {
        named.append(member)
      }
    }
    let ordered = indexed.sorted { left, right in
      left.index < right.index
    }
    return ordered.map(\.member) + named
  }

  /// The key as an ECMAScript array index — a canonical decimal integer below
  /// 2^32 - 1 — or nil.
  private static func arrayIndex(_ key: String) -> UInt64? {
    let units = Array(key.utf16)
    guard !units.isEmpty, units.count <= 10, units.allSatisfy(CodeUnits.isASCIIDigit) else {
      return nil
    }
    guard units.count == 1 || units[0] != 0x30 else {
      return nil
    }
    guard let number = UInt64(key), number < 4_294_967_295 else {
      return nil
    }
    return number
  }

  /// `stringifyNumber` through the `int`/`float` tags: `JSON.stringify`
  /// spelling, `-0` kept, and YAML's words for the non-finite.
  private static func numberText(_ number: Double) -> String {
    if number.isNaN {
      return ".nan"
    }
    if number.isInfinite {
      return number < 0 ? "-.inf" : ".inf"
    }
    if number == 0, number.sign == .minus {
      return "-0"
    }
    return JavaScriptNumber.text(number)
  }
}
