struct DefinitionFileReader: DefinitionFileReading {
  private let checker: any UseCaseChecking

  init(checker: any UseCaseChecking = UseCaseChecker()) {
    self.checker = checker
  }

  func read(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) throws(DefinitionFileReadingError) -> DefinitionFile {
    var findings = AuthoredFindings(file: file)

    guard
      let root = findings.attempt({ () throws(AuthoredShapeError) in
        try AuthoredObject(
          value,
          at: "",
        )
      })
    else {
      throw .invalid(findings.sorted)
    }

    let prefix = findings.attemptOptional { () throws(AuthoredShapeError) in
      try root.optionalIdentifier(
        "prefix",
        parsing: Namespace.init(validating:),
      )
    }
    let items = findings.attempt { () throws(AuthoredShapeError) in
      try useCaseItems(of: root)
    }

    var useCases: [UseCaseDefinition] = []

    for (index, item) in (items ?? []).enumerated() {
      if let useCase = readUseCase(
        item,
        number: index + 1,
        findings: &findings,
      ) {
        useCases.append(useCase)
      }
    }

    guard findings.isClean else {
      throw .invalid(findings.sorted)
    }

    return DefinitionFile(
      prefix: prefix,
      useCases: useCases,
    )
  }

  private func useCaseItems(of root: AuthoredObject) throws(AuthoredShapeError)
    -> [AuthoredValue]
  {
    guard root.contains("use_cases") else {
      throw .missing(location: "use_cases")
    }

    return try root.items("use_cases")
  }

  private func readUseCase(
    _ item: AuthoredValue,
    number: Int,
    findings: inout AuthoredFindings,
  ) -> UseCaseDefinition? {
    let object: AuthoredObject
    do {
      object = try AuthoredObject(
        item,
        at: "",
      )
    } catch {
      findings.add(
        .invalidValue,
        "use case number \(number): \(error.description)",
      )
      return nil
    }

    do {
      let useCase = try UseCaseDefinition(authored: object)
      let problems = checker.check(
        useCase,
        file: findings.file,
      )
      findings.add(contentsOf: problems)

      return useCase
    } catch {
      findings.add(
        .invalidValue,
        "\(Self.label(of: object, number: number)): \(error.description)",
      )

      return nil
    }
  }

  /// `use case 'login'`, or the use case's place in the file when its id cannot be read.
  private static func label(
    of object: AuthoredObject,
    number: Int,
  ) -> String {
    guard case let .string(text)? = object.value(for: "id") else {
      return "use case number \(number)"
    }

    return "use case \(AuthoredValue.quote(text))"
  }
}
