import UseCasesCore

/// The YAML-ish dump of an envelope's `data` (render.ts `renderHumanValue`):
/// nulls skipped inside objects, empty arrays as `(none)`, scalar arrays on
/// one line, and everything else nested two spaces per level.
enum HumanValueDumper {
  static func lines(
    for value: JSONValue?,
    depth: Int,
  ) -> [String] {
    let pad = String(repeating: "  ", count: depth)
    switch value {
    case .none, .null:
      return []
    case let .array(items):
      return arrayLines(items, depth: depth, pad: pad)
    case let .object(object):
      return objectLines(object, depth: depth, pad: pad)
    case let .some(scalar):
      return ["\(pad)\(EnvelopeRenderer.scalarText(scalar))"]
    }
  }

  private static func arrayLines(
    _ items: [JSONValue],
    depth: Int,
    pad: String,
  ) -> [String] {
    var out: [String] = []
    for item in items {
      if isStructured(item) {
        out.append("\(pad)-")
        out += lines(for: item, depth: depth + 1)
      } else {
        out.append("\(pad)- \(EnvelopeRenderer.scalarText(item))")
      }
    }
    return out
  }

  private static func objectLines(
    _ object: JSONObject,
    depth: Int,
    pad: String,
  ) -> [String] {
    var out: [String] = []
    for (key, item) in object.pairs {
      switch item {
      case .null:
        continue
      case let .array(members) where members.isEmpty:
        out.append("\(pad)\(key): (none)")
      case let .array(members) where !members.contains(where: isStructured):
        out
          .append(
            "\(pad)\(key): \(members.map(EnvelopeRenderer.scalarText).joined(separator: ", "))",
          )
      case .array, .object:
        out.append("\(pad)\(key):")
        out += lines(for: item, depth: depth + 1)
      default:
        out.append("\(pad)\(key): \(EnvelopeRenderer.scalarText(item))")
      }
    }
    return out
  }

  private static func isStructured(_ value: JSONValue) -> Bool {
    switch value {
    case .array, .object: true
    default: false
    }
  }
}
