/// What a file's name says about whether it is a use case definition (chapter 04, "Definition
/// discovery"): the ending is spelt `.yml` or `.yaml`, in lower case.
enum DefinitionFileName: Equatable, Sendable {
  /// Ends `.yml` or `.yaml`: a definition.
  case definition

  /// Ends `.yml` or `.yaml` in another casing: INVALID, to be renamed to `renamed`.
  case wrongCase(renamed: String)

  /// Any other name: not a definition.
  case notYAML

  /// Reads a name. Casing is folded for ASCII letters only, so only `.YML`, `.Yaml` and the
  /// like count as the wrong spelling of a YAML ending.
  init(_ name: String) {
    let scalars = Array(name.unicodeScalars)

    guard
      let dot = scalars.lastIndex(of: "."),
      dot < scalars.index(before: scalars.endIndex)
    else {
      self = .notYAML
      return
    }

    let ending = scalars[scalars.index(after: dot)...].map(Self.foldedToLowerCase)
    let folded = String(String.UnicodeScalarView(ending))

    guard folded == "yml" || folded == "yaml" else {
      self = .notYAML
      return
    }

    if scalars[scalars.index(after: dot)...].elementsEqual(ending) {
      self = .definition
    } else {
      let stem = String(String.UnicodeScalarView(scalars[...dot]))
      self = .wrongCase(renamed: stem + folded)
    }
  }

  private static func foldedToLowerCase(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
    guard scalar.value >= 0x41, scalar.value <= 0x5A else {
      return scalar
    }

    return Unicode.Scalar(scalar.value + 0x20) ?? scalar
  }
}
