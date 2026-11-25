struct ScopeConfigurationLoader: ScopeConfigurationLoading {
  private let yamlReader: any YAMLReading
  private let schema: any SchemaChecking
  private let configurationReader: any ScopeConfigurationReading

  /// - Parameter schema: The checker for the workspace schema.
  init(
    yamlReader: any YAMLReading,
    schema: any SchemaChecking,
    configurationReader: any ScopeConfigurationReading,
  ) {
    self.yamlReader = yamlReader
    self.schema = schema
    self.configurationReader = configurationReader
  }

  func load(
    fromText text: String,
    at path: WorkspacePath,
  ) throws(ScopeSettingsError) -> ScopeConfiguration {
    let value: AuthoredValue

    do {
      value = try yamlReader.read(
        text,
        file: path.text,
        kind: .settings,
      )
    } catch {
      throw Self.refusal([error.diagnostic(in: path)])
    }

    let failures = schema.check(value)

    guard failures.isEmpty else {
      throw Self.refusal(failures.map { failure in failure.diagnostic(in: path) }.sorted())
    }

    do {
      return try configurationReader.read(
        value,
        file: path,
        role: role(of: value, at: path),
      )
    } catch {
      switch error {
      case let .invalid(diagnostics):
        throw Self.refusal(diagnostics.sorted())
      }
    }
  }

  /// The root's file sits at the top of the workspace. A file below it that says `root: true` is
  /// a nested workspace's own root, whose settings are its own business; every other file is a
  /// child scope's.
  private func role(
    of value: AuthoredValue,
    at path: WorkspacePath,
  ) -> ScopeRole {
    if path.parent?.isRoot == true {
      return .root
    }

    guard case let .object(members) = value else {
      return .child
    }

    let declaresRoot = members.contains { member in
      member.key.isExactlyEqual(to: "root") && member.value == .boolean(true)
    }

    return declaresRoot ? .root : .child
  }

  private static func refusal(_ diagnostics: [Diagnostic]) -> ScopeSettingsError {
    ScopeSettingsError(
      problems: diagnostics.map { diagnostic in
        ScopeSettingsProblem(
          position: diagnostic.position,
          code: diagnostic.code,
          message: diagnostic.message,
        )
      },
    )
  }
}
