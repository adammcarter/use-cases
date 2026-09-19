/// One pass of `validateSkillAssets` over a workspace: the diagnostics,
/// skills and command references gathered so far, in the TypeScript's order.
struct SkillAssetValidation {
  let root: String
  var diagnostics: [Diagnostic] = []
  var skills: [SkillAssetSummary] = []
  var commandReferences: [SkillCommandReference] = []

  /// The skills directory exists and lists every canonical skill.
  mutating func checkSkillDirectory() throws(SkillAssetValidationError) {
    let skillRoot = NodePath.join(root, "skills")
    guard NodeFile.exists(atPath: skillRoot) else {
      diagnostics.append(Diagnostic(
        code: "skills.root_missing",
        message: "Missing skills directory.",
        sourcePath: "skills",
      ))
      return
    }
    let names: [String]
    do throws(FileAccessError) {
      names = try NodeFile.directoryNames(atPath: skillRoot)
    } catch {
      throw .fileAccess(error)
    }
    let missing = CanonicalSkill.allCases.map(\.rawValue).filter { expected in
      !names.contains { name in
        JavaScriptString.identical(name, expected)
      }
    }
    for expected in missing {
      diagnostics.append(Diagnostic(
        code: "skills.missing",
        message: "Missing canonical skill '\(expected)'.",
        sourcePath: "skills/\(expected)/SKILL.md",
        entityIdentifier: expected,
      ))
    }
  }

  /// Every canonical skill's `SKILL.md` that exists, read in canonical order.
  mutating func readSkills() throws(SkillAssetValidationError) {
    var names: [String] = []
    for skillName in CanonicalSkill.allCases.map(\.rawValue) {
      let sourcePath = "skills/\(skillName)/SKILL.md"
      let fullPath = NodePath.join(root, sourcePath)
      guard NodeFile.exists(atPath: fullPath) else {
        continue
      }
      let source = try read(fullPath)
      let frontmatter = try frontmatter(source, sourcePath: sourcePath)
      let name = frontmatter?.name ?? ""
      let description = frontmatter?.description ?? ""
      checkIdentity(
        name: name,
        description: description,
        skillName: skillName,
        sourcePath: sourcePath,
        earlierNames: names,
      )
      names.append(name)
      extractCommandReferences(source, sourcePath: sourcePath)
      checkForbiddenClaims(source, sourcePath: sourcePath)
      let isComplete = diagnostics.allSatisfy { diagnostic in
        !Self.isSame(diagnostic.entityIdentifier, name)
          && !Self.isSame(diagnostic.sourcePath, sourcePath)
      }
      skills.append(SkillAssetSummary(
        name: name,
        path: sourcePath,
        description: description,
        isComplete: isComplete,
      ))
    }
  }

  /// The bootstrap's sections, boundaries, commands and claims; the required
  /// sections it holds, in required order.
  mutating func readBootstrap() throws(SkillAssetValidationError) -> [String] {
    let path = SkillAssetValidator.bootstrapPath
    let fullPath = NodePath.join(root, path)
    guard NodeFile.exists(atPath: fullPath) else {
      diagnostics.append(Diagnostic(
        code: "skills.bootstrap_missing",
        message: "Missing use-cases bootstrap.",
        sourcePath: path,
      ))
      return []
    }
    let source = try read(fullPath)
    var sections: [String] = []
    for section in SkillAssetValidator.bootstrapSections {
      if SkillText.contains(source, section) {
        sections.append(section)
      } else {
        diagnostics.append(Diagnostic(
          code: "skills.bootstrap_section_missing",
          message: "Bootstrap missing '\(section)'.",
          sourcePath: path,
        ))
      }
    }
    for phrase in SkillAssetValidator.bootstrapBoundaries
      where !SkillText.contains(source, phrase)
    {
      diagnostics.append(Diagnostic(
        code: "skills.bootstrap_boundary_missing",
        message: "Bootstrap missing '\(phrase)'.",
        sourcePath: path,
      ))
    }
    extractCommandReferences(source, sourcePath: path)
    checkForbiddenClaims(source, sourcePath: path)
    return sections
  }

  /// The activation docs' decision-tree markers and claims.
  mutating func readActivation() throws(SkillAssetValidationError) {
    let path = SkillAssetValidator.activationPath
    let fullPath = NodePath.join(root, path)
    guard NodeFile.exists(atPath: fullPath) else {
      diagnostics.append(Diagnostic(
        code: "skills.activation_missing",
        message: "Missing activation docs.",
        sourcePath: path,
      ))
      return
    }
    let source = try read(fullPath)
    for marker in SkillAssetValidator.activationMarkers where !SkillText.contains(source, marker) {
      diagnostics.append(Diagnostic(
        code: "skills.activation_tree_missing",
        message: "Activation docs missing '\(marker)'.",
        sourcePath: path,
      ))
    }
    checkForbiddenClaims(source, sourcePath: path)
  }

  /// Every reference to a command the CLI does not have.
  mutating func checkCommandReferences() {
    for reference in commandReferences where !KnownCliCommands.isKnown(reference.command) {
      diagnostics.append(Diagnostic(
        code: "skills.unknown_cli_command",
        message: "Unknown CLI command '\(reference.command)'.",
        sourcePath: reference.sourcePath,
        entityIdentifier: reference.command,
      ))
    }
  }

  /// The frontmatter name matches the directory, the description is specific
  /// and the name is not an earlier skill's.
  private mutating func checkIdentity(
    name: String,
    description: String,
    skillName: String,
    sourcePath: String,
    earlierNames names: [String],
  ) {
    if !JavaScriptString.identical(name, skillName) {
      diagnostics.append(Diagnostic(
        code: "skills.name_mismatch",
        message: "Skill frontmatter name must match directory name.",
        sourcePath: sourcePath,
        entityIdentifier: name,
      ))
    }
    if description.utf16.count < 40 {
      diagnostics.append(Diagnostic(
        code: "skills.description_missing",
        message: "Skill description must be specific.",
        sourcePath: sourcePath,
        entityIdentifier: name.isEmpty ? skillName : name,
      ))
    }
    let isDuplicate = names.contains { earlier in
      JavaScriptString.identical(earlier, name)
    }
    if !name.isEmpty, isDuplicate {
      diagnostics.append(Diagnostic(
        code: "skills.duplicate_name",
        message: "Duplicate skill name '\(name)'.",
        sourcePath: sourcePath,
        entityIdentifier: name,
      ))
    }
  }

  /// `value === other` for a nullable string.
  private static func isSame(
    _ value: String?,
    _ other: String,
  ) -> Bool {
    guard let value else {
      return false
    }
    return JavaScriptString.identical(value, other)
  }

  private func read(_ path: String) throws(SkillAssetValidationError) -> String {
    do throws(FileAccessError) {
      return try NodeFile.readText(atPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }

  /// `parseFrontmatter`: nil when missing or unparseable, each recorded.
  private mutating func frontmatter(
    _ source: String,
    sourcePath: String,
  ) throws(SkillAssetValidationError) -> (name: String, description: String)? {
    guard let block = SkillText.frontmatter(source) else {
      diagnostics.append(Diagnostic(
        code: "skills.frontmatter_missing",
        message: "Skill is missing YAML frontmatter.",
        sourcePath: sourcePath,
      ))
      return nil
    }
    let parsed = YamlParser.parseToJSON(source: block, sourcePath: sourcePath)
    guard parsed.isValid, let value = parsed.value else {
      diagnostics += parsed.diagnostics
      return nil
    }
    guard value != .null else {
      throw .nullFrontmatter
    }
    return (value["name"]?.stringValue ?? "", value["description"]?.stringValue ?? "")
  }

  private mutating func extractCommandReferences(
    _ source: String,
    sourcePath: String,
  ) {
    for capture in SkillText.cliCommandCaptures(source) {
      let tokens = SkillText.splitOnWhitespace(JavaScriptString.trim(capture))
      if tokens.count >= 2 {
        commandReferences.append(SkillCommandReference(
          command: tokens[0] + " " + tokens[1],
          sourcePath: sourcePath,
        ))
      }
    }
  }

  private mutating func checkForbiddenClaims(
    _ source: String,
    sourcePath: String,
  ) {
    for claim in SkillForbiddenClaim.all where SkillText.matches(claim, in: source) {
      diagnostics.append(Diagnostic(
        code: claim.code,
        message: claim.message,
        sourcePath: sourcePath,
      ))
    }
  }
}
