/// The two pieces of node's POSIX `path` module the matrix code needs beyond
/// ``NodePath/join(_:)``: `extname` and `relative`, spelled over UTF-16 code
/// units as node spells them.
extension NodePath {
  /// `path.extname(path)`: the last `.`-suffix of the final segment, or `""`
  /// when the segment has none or IS its dot (`.yml` has no extension; `..yml`
  /// has `.yml`).
  static func extname(_ path: String) -> String {
    let units = Array(path.utf16)
    var startDot = -1
    var startPart = 0
    var end = -1
    var matchedSlash = true
    var preDotState = 0
    var index = units.count - 1
    while index >= 0 {
      let unit = units[index]
      if unit == CodeUnits.solidus {
        if !matchedSlash {
          startPart = index + 1
          break
        }
        index -= 1
        continue
      }
      if end == -1 {
        matchedSlash = false
        end = index + 1
      }
      if unit == CodeUnits.fullStop {
        if startDot == -1 {
          startDot = index
        } else if preDotState != 1 {
          preDotState = 1
        }
      } else if startDot != -1 {
        preDotState = -1
      }
      index -= 1
    }
    if startDot == -1 || end == -1 || preDotState == 0
      || (preDotState == 1 && startDot == end - 1 && startDot == startPart + 1)
    {
      return ""
    }
    return CodeUnits.string(units[startDot ..< end])
  }

  /// `path.relative(from, to)` for two absolute paths: the `..` climb out of
  /// `origin` and the descent into `destination`, or `""` when they are the
  /// same path. Spelled as node's loop spells it, so a shared prefix that ends
  /// mid-segment is judged as node judges it.
  static func relative(
    from origin: String,
    to destination: String,
  ) -> String {
    let originUnits = resolvedAbsolute(origin)
    let destinationUnits = resolvedAbsolute(destination)
    if originUnits == destinationUnits {
      return ""
    }
    switch sharedPrefix(originUnits, destinationUnits) {
    case let .descendant(tail):
      return CodeUnits.string(tail)
    case let .lastCommonSeparator(separator):
      let climb = climbOut(of: originUnits, above: separator)
      return CodeUnits.string(climb + destinationUnits[(1 + separator)...])
    }
  }

  private enum SharedPrefix {
    /// `destination` lies inside `origin`; this is the part below it.
    case descendant(ArraySlice<UInt16>)

    /// The offset, after the root `/`, of the last separator both share.
    case lastCommonSeparator(Int)
  }

  private static func sharedPrefix(
    _ origin: [UInt16],
    _ destination: [UInt16],
  ) -> SharedPrefix {
    let length = min(origin.count, destination.count) - 1
    var lastCommonSeparator = -1
    var index = 0
    while index < length, origin[1 + index] == destination[1 + index] {
      if origin[1 + index] == CodeUnits.solidus {
        lastCommonSeparator = index
      }
      index += 1
    }
    guard index == length else {
      return .lastCommonSeparator(lastCommonSeparator)
    }
    return prefixExhausted(origin, destination, at: index, lastCommonSeparator: lastCommonSeparator)
  }

  /// One path is a prefix of the other, code unit for code unit.
  private static func prefixExhausted(
    _ origin: [UInt16],
    _ destination: [UInt16],
    at index: Int,
    lastCommonSeparator: Int,
  ) -> SharedPrefix {
    if destination.count - 1 > index {
      if destination[1 + index] == CodeUnits.solidus {
        return .descendant(destination[(1 + index + 1)...])
      }
      if index == 0 {
        return .descendant(destination[(1 + index)...])
      }
    } else if origin.count - 1 > index {
      if origin[1 + index] == CodeUnits.solidus {
        return .lastCommonSeparator(index)
      }
      if index == 0 {
        return .lastCommonSeparator(0)
      }
    }
    return .lastCommonSeparator(lastCommonSeparator)
  }

  /// One `..` for every segment of `origin` past the shared separator.
  private static func climbOut(
    of origin: [UInt16],
    above separator: Int,
  ) -> [UInt16] {
    var out: [UInt16] = []
    var position = 1 + separator + 1
    while position <= origin.count {
      if position == origin.count || origin[position] == CodeUnits.solidus {
        out += out.isEmpty ? parentDirectory : [CodeUnits.solidus] + parentDirectory
      }
      position += 1
    }
    return out
  }

  /// `path.resolve(path)` for an absolute path: normalized, with no trailing
  /// separator unless it is the root.
  private static func resolvedAbsolute(_ path: String) -> [UInt16] {
    var units = Array(normalize(path).utf16)
    if units.count > 1, units.last == CodeUnits.solidus {
      units.removeLast()
    }
    return units
  }

  private static let parentDirectory: [UInt16] = [CodeUnits.fullStop, CodeUnits.fullStop]
}
