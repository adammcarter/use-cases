struct ScopeConfigurationReader: ScopeConfigurationReading {
  func read(
    _ value: AuthoredValue,
    file: WorkspacePath,
    role: ScopeRole,
  ) throws(ScopeConfigurationReadingError) -> ScopeConfiguration {
    var findings = AuthoredFindings(file: file)

    let object: AuthoredObject
    do {
      object = try AuthoredObject(
        value,
        at: "",
      )
    } catch {
      findings.add(
        .invalidValue,
        error.description,
      )
      throw .invalid(findings.sorted)
    }

    let schemaVersion = findings.attempt { () throws(AuthoredShapeError) in
      try object.requiredInteger("schema_version")
    }
    let declaresRoot = findings.attemptOptional { () throws(AuthoredShapeError) in
      try object.optionalBoolean("root")
    }
    let prefix = findings.attemptOptional { () throws(AuthoredShapeError) in
      try object.optionalIdentifier(
        "prefix",
        parsing: Namespace.init(validating:),
      )
    }
    let useCasesDirectory = readUseCasesDirectory(
      of: object,
      findings: &findings,
    )
    let rootSettings = readRootSettings(
      of: object,
      role: role,
      findings: &findings,
    )

    guard
      findings.isClean,
      let schemaVersion,
      let useCasesDirectory
    else {
      throw .invalid(findings.sorted)
    }

    return ScopeConfiguration(
      schemaVersion: schemaVersion,
      declaresRoot: declaresRoot == true,
      prefix: prefix,
      useCasesDirectory: useCasesDirectory,
      rootSettings: rootSettings,
    )
  }

  /// `use_cases_dir`, which may not leave the scope.
  private func readUseCasesDirectory(
    of object: AuthoredObject,
    findings: inout AuthoredFindings,
  ) -> WorkspacePath? {
    do {
      return try object.path(
        "use_cases_dir",
        defaultText: ScopeConfiguration.defaultUseCasesDirectoryText,
      )
    } catch {
      findings.add(
        .invalidValue,
        Self.describe(directoryError: error),
      )
      return nil
    }
  }

  /// The root's settings with their defaults, or nil for a child scope; a child that writes one
  /// is a finding.
  private func readRootSettings(
    of object: AuthoredObject,
    role: ScopeRole,
    findings: inout AuthoredFindings,
  ) -> RootSettings? {
    switch role {
    case .child:
      for setting in RootOnlySetting.allCases where object.contains(setting.key) {
        findings.add(
          .rootOnlySetting,
          "\(setting.key) is root-only: write it in the workspace root's use-cases.yml, "
            + "not in a child scope",
        )
      }

      return nil
    case .root:
      let freshness = findings.attempt { () throws(AuthoredShapeError) in
        try readFreshness(of: object)
      }
      let exclusions = findings.attempt { () throws(AuthoredShapeError) in
        try object.optionalObject("discovery")?.patterns("exclude") ?? []
      }
      let signOff = findings.attemptOptional { () throws(AuthoredShapeError) in
        try object.optionalChoice(
          "sign_off",
          as: SignOffRequirement.self,
        )
      }

      return RootSettings(
        freshness: freshness ?? .standard,
        discoveryExclusions: exclusions ?? [],
        signOff: signOff,
      )
    }
  }

  private func readFreshness(of object: AuthoredObject) throws(AuthoredShapeError)
    -> FreshnessPolicy
  {
    guard let written = try object.optionalObject("freshness") else {
      return .standard
    }

    return try FreshnessPolicy(authored: written)
  }

  /// A path that leaves the scope is worded for the scope; the workspace wording of the path
  /// type would name the wrong boundary.
  private static func describe(directoryError error: AuthoredShapeError) -> String {
    guard case let .invalidPath(location, pathError) = error else {
      return error.description
    }

    switch pathError {
    case .absolute, .driveLetter, .parentSegment:
      return "\(location): '\(pathError.offendingText)' leaves the scope; "
        + "use_cases_dir must name a folder inside the scope's directory"
    default:
      return error.description
    }
  }
}
