/// Holds a use case that is sent to the rules of a definition file, by reading it as the only
/// use case of one.
struct UseCaseInputChecker: UseCaseInputChecking {
  private let schemaLoader: any SchemaLoading
  private let technicalFieldChecker: any TechnicalFieldChecking
  private let markerBindingChecker: any MarkerBindingChecking
  private let fileReader: any DefinitionFileReading

  init(
    schemaLoader: any SchemaLoading = BundledSchemaLoader(),
    technicalFieldChecker: any TechnicalFieldChecking = TechnicalFieldChecker(),
    markerBindingChecker: any MarkerBindingChecking = MarkerBindingChecker(),
    fileReader: any DefinitionFileReading = DefinitionFileReader(),
  ) {
    self.schemaLoader = schemaLoader
    self.technicalFieldChecker = technicalFieldChecker
    self.markerBindingChecker = markerBindingChecker
    self.fileReader = fileReader
  }

  func check(_ input: AuthoredInput) throws(UseCaseEditingError) -> CheckedUseCase {
    guard
      let object = try? AuthoredObject(
        input.value,
        at: "",
      ),
      case let .string(text)? = object.value(for: "id")
    else {
      throw .notAUseCase(name: input.name)
    }

    let identifier: UseCaseIdentifier

    do {
      identifier = try UseCaseIdentifier(validating: text)
    } catch {
      throw .invalidIdentifier(message: error.description)
    }

    guard let local = identifier.namespace.segments.last else {
      throw .notAUseCase(name: input.name)
    }

    let definition = try definition(
      of: AuthoredMember.replacing(
        "id",
        with: .string(local.text),
        in: object.members,
      ),
      named: input.name,
    )

    return CheckedUseCase(
      identifier: identifier,
      definition: definition,
    )
  }

  private func definition(
    of members: [AuthoredMember],
    named name: String,
  ) throws(UseCaseEditingError) -> UseCaseDefinition {
    let reader: DefinitionFileLoader

    do {
      reader = try DefinitionFileLoader(
        fileSystem: LocalFileSystem(),
        yamlReader: StrictYAMLReader(),
        technicalFieldChecker: technicalFieldChecker,
        markerBindingChecker: markerBindingChecker,
        schema: schemaLoader.loadChecker(for: .useCases),
        fileReader: fileReader,
      )
    } catch {
      throw .schemasUnavailable(message: "\(error)")
    }

    let file = WorkspacePath.root.appending(literal: "input")
    let document = AuthoredValue.object([
      AuthoredMember(
        key: "use_cases",
        value: .array([.object(members)]),
      ),
    ])

    let useCase: UseCaseDefinition?

    do {
      useCase = try reader.definitionFile(
        from: document,
        at: file,
      ).useCases.first
    } catch {
      switch error {
      case let .invalid(problems):
        throw .invalidUseCase(
          name: name,
          problems: problems.map(\.message),
        )
      }
    }

    guard let useCase else {
      throw .notAUseCase(name: name)
    }

    return useCase
  }
}

private extension AuthoredMember {
  /// The members with the value of one key swapped, in the place it was written.
  static func replacing(
    _ key: String,
    with value: AuthoredValue,
    in members: [AuthoredMember],
  ) -> [AuthoredMember] {
    members.map { member in
      member.key.isExactlyEqual(to: key)
        ? AuthoredMember(
          key: member.key,
          value: value,
        )
        : member
    }
  }
}
