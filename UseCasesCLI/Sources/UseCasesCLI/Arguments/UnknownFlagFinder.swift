/// Unknown-flag detection (packages/cli/src/args/validate.ts).
///
/// Conservative on purpose: the allowlist is every flag any command declares
/// plus the flags handlers read straight off the arguments, so a typo is caught
/// while no real flag is ever refused.
enum UnknownFlagFinder {
  static let globalFlags: Set<String> = [
    "--json",
    "--help",
    "-h",
    "--version",
    "-v",
    "--strict",
    "--repo",
    "--data-root",
    "--component",
    "--all",
    "--dry-run",
    "--flag",
    "--force",
    "--host",
    "--installed-root",
    "--mode",
    "--out",
    "--revert",
    "--source",
    "--tarball",
    "--template",
    "--write",
  ]

  /// The globals that consume the following token as their value.
  static let globalValueFlags: Set<String> = [
    "--repo",
    "--data-root",
    "--component",
    "--flag",
    "--host",
    "--installed-root",
    "--mode",
    "--out",
    "--source",
    "--tarball",
    "--template",
  ]

  /// The unknown flag tokens, in argument order; empty when all are known.
  static func unknownFlags(
    in arguments: [String],
    commands: [CommandSpecification],
  ) -> [String] {
    var known = globalFlags
    var valueBearing = globalValueFlags
    for flag in commands.flatMap(\.flags) {
      known.insert(flag.name)
      if flag.kind != .boolean {
        valueBearing.insert(flag.name)
      }
    }

    var unknown: [String] = []
    var index = 0
    while index < arguments.count {
      let token = arguments[index]
      if token == "--" {
        break
      }
      if valueBearing.contains(token) {
        index += 2
        continue
      }
      if looksLikeFlag(token), !known.contains(token) {
        unknown.append(token)
      }
      index += 1
    }
    return unknown
  }

  /// `--anything`, or a dash and one ASCII letter.
  private static func looksLikeFlag(_ token: String) -> Bool {
    if token.hasPrefix("--") {
      return true
    }
    let scalars = Array(token.unicodeScalars)
    guard scalars.count == 2, scalars[0] == "-" else {
      return false
    }
    return ("a" ... "z").contains(scalars[1]) || ("A" ... "Z").contains(scalars[1])
  }
}
