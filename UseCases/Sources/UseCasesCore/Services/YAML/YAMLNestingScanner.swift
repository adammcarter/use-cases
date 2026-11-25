/// Counts nesting by reading the text line by line: block lists and mappings by their
/// indentation, flow lists and mappings by their brackets. It keeps no recursion, so no depth
/// can overflow it.
struct YAMLNestingScanner: YAMLNestingScanning {
  func firstLine(
    deeperThan limit: Int,
    in source: YAMLSourceText,
  ) -> Int? {
    var state = YAMLNestingState(limit: limit)

    for number in 1 ... max(source.lineCount, 1) {
      state.read(source.scalars(ofLine: number))

      if state.exceeded {
        return number
      }
    }

    return nil
  }
}
