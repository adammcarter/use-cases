/// Whether a host can reach the skills at all: the Claude plugin manifest
/// names a directory that holds them, and the marketplace offers the plugin
/// so the manifest is read (`validateHostRegistration`).
enum SkillHostRegistration {
  static let manifestPath = ".claude-plugin/plugin.json"
  static let marketplacePath = ".claude-plugin/marketplace.json"
  static let pluginName = "use-cases"
  /// Claude always scans `skills/` at the plugin root, declared or not.
  static let implicitSkillRoots = ["./skills"]

  //: @use-case:skills.assets.unreachable_skills_fail_doctor
  static func validate(
    root: String,
    diagnostics: inout [Diagnostic],
  ) -> SkillHostRegistrationResult {
    let manifestFullPath = NodePath.join(root, manifestPath)
    guard NodeFile.exists(atPath: manifestFullPath) else {
      diagnostics.append(Diagnostic(
        code: "skills.host_manifest_missing",
        message: "Missing Claude plugin manifest.",
        sourcePath: manifestPath,
      ))
      return SkillHostRegistrationResult(isComplete: false, hosts: [])
    }

    let declaresSkillRoot = declaredSkillRoots(root: root, manifestFullPath: manifestFullPath)
      .contains { candidate in
        CanonicalSkill.allCases.allSatisfy { skill in
          NodeFile.exists(atPath: NodePath.join(root, candidate, skill.rawValue, "SKILL.md"))
        }
      }
    if !declaresSkillRoot {
      diagnostics.append(Diagnostic(
        code: "skills.host_not_declared",
        message: "Claude plugin manifest does not declare a directory containing the "
          + "canonical skills.",
        sourcePath: manifestPath,
      ))
    }

    let isInstallable = marketplaceListsPlugin(NodePath.join(root, marketplacePath))
    if !isInstallable {
      diagnostics.append(Diagnostic(
        code: "skills.host_not_installable",
        message: "Marketplace manifest does not offer '\(pluginName)', so the plugin manifest "
          + "is never read.",
        sourcePath: marketplacePath,
      ))
    }

    return SkillHostRegistrationResult(
      isComplete: declaresSkillRoot && isInstallable,
      hosts: [SkillHostRegistrationSummary(
        host: "claude",
        manifestPath: manifestPath,
        declaresSkillRoot: declaresSkillRoot,
        isInstallable: isInstallable,
      )],
    )
  }

  //: @use-case:end skills.assets.unreachable_skills_fail_doctor

  /// The manifest's `skills` (a string or the strings of an array) and the
  /// implicit root, each without one leading `./` or any trailing `/`, kept
  /// when non-empty and inside the root.
  private static func declaredSkillRoots(
    root: String,
    manifestFullPath: String,
  ) -> [String] {
    let declared = readJSON(manifestFullPath)?.objectValue?["skills"]
    let entries: [String] = switch declared {
    case let .string(entry): [entry]
    case let .array(items): items.compactMap(\.stringValue)
    default: []
    }
    return (entries + implicitSkillRoots)
      .map(trimmed)
      .filter { entry in
        !entry.isEmpty
          && PathContainment.isContained(root: root, target: NodePath.join(root, entry))
      }
  }

  /// `.replace(/^\.\//, "").replace(/\/+$/, "")`.
  private static func trimmed(_ entry: String) -> String {
    var units = Array(entry.utf16)
    if units.starts(with: [CodeUnits.fullStop, CodeUnits.solidus]) {
      units.removeFirst(2)
    }
    while units.last == CodeUnits.solidus {
      units.removeLast()
    }
    return CodeUnits.string(units)
  }

  private static func marketplaceListsPlugin(_ path: String) -> Bool {
    guard let plugins = readJSON(path)?.objectValue?["plugins"]?.arrayValue else {
      return false
    }
    return plugins.contains { plugin in
      guard let name = plugin.objectValue?["name"]?.stringValue else {
        return false
      }
      return JavaScriptString.identical(name, pluginName)
    }
  }

  /// `readJsonOrNull`: nil for a missing, unreadable or unparseable file.
  private static func readJSON(_ path: String) -> JSONValue? {
    guard NodeFile.exists(atPath: path),
          let text = try? NodeFile.readText(atPath: path)
    else {
      return nil
    }
    return try? JSONParser.parse(pairedSurrogateEscapes(text))
  }

  /// `JSON.parse` accepts a `\uD800`-style escape with no partner and keeps
  /// the lone surrogate, where ``JSONParser`` refuses the document. A Swift
  /// string cannot hold one, so each such escape becomes `\uFFFD`: the file
  /// still parses, and no member it could affect compares equal to a plain
  /// name either way.
  private static func pairedSurrogateEscapes(_ text: String) -> String {
    let units = Array(text.utf16)
    var output: [UInt16] = []
    var index = 0
    while index < units.count {
      guard units[index] == CodeUnits.reverseSolidus, index + 1 < units.count else {
        output.append(units[index])
        index += 1
        continue
      }
      if let high = escapedUnit(units, at: index), (0xD800 ... 0xDBFF).contains(high),
         let low = escapedUnit(units, at: index + 6), (0xDC00 ... 0xDFFF).contains(low)
      {
        output += units[index ..< index + 12]
        index += 12
      } else if let unit = escapedUnit(units, at: index), (0xD800 ... 0xDFFF).contains(unit) {
        output += Array("\\ufffd".utf16)
        index += 6
      } else {
        output += units[index ... index + 1]
        index += 2
      }
    }
    return CodeUnits.string(output)
  }

  /// The code unit a `\uXXXX` escape starting at `index` names.
  private static func escapedUnit(
    _ units: [UInt16],
    at index: Int,
  ) -> UInt16? {
    guard index + 6 <= units.count,
          units[index] == CodeUnits.reverseSolidus,
          units[index + 1] == 0x75
    else {
      return nil
    }
    return UInt16(CodeUnits.string(units[index + 2 ..< index + 6]), radix: 16)
  }
}
