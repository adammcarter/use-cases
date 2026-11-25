struct BridgeSettingsAdvisor: BridgeSettingsAdvising {
  func warnings(
    for settings: BridgeSettings,
    writesValidations: Bool,
    in file: WorkspacePath,
  ) -> [Diagnostic] {
    if writesValidations, settings.validations.isEmpty {
      return [.noValidations(in: file)]
    }

    return settings.validations.flatMap { validation in
      warnings(
        of: validation,
        in: file,
      )
    }
  }

  private func warnings(
    of validation: BridgeValidation,
    in file: WorkspacePath,
  ) -> [Diagnostic] {
    guard let executable = validation.run?.first else {
      return [.validationWithoutRun(validation.identifier, in: file)]
    }

    guard Self.isAbsolute(executable) else {
      return []
    }

    return [
      .absoluteRunCommand(
        executable,
        of: validation.identifier,
        in: file,
      ),
    ]
  }

  /// Whether a command names its program by an absolute path on any system: from the root, from
  /// a network share or from a drive.
  private static func isAbsolute(_ executable: String) -> Bool {
    if executable.hasPrefix("/") || executable.hasPrefix("\\") {
      return true
    }

    let scalars = Array(executable.unicodeScalars)

    guard scalars.count >= 3, scalars[1] == ":", scalars[2] == "/" || scalars[2] == "\\" else {
      return false
    }

    return ("a" ... "z").contains(Character(scalars[0]).lowercased())
  }
}
