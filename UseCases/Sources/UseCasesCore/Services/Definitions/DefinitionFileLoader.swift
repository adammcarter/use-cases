import Foundation

struct DefinitionFileLoader: DefinitionFileLoading, DefinitionValueReading {
  private let fileSystem: any FileSystemReading
  private let yamlReader: any YAMLReading
  private let technicalFieldChecker: any TechnicalFieldChecking
  private let markerBindingChecker: any MarkerBindingChecking
  private let schema: any SchemaChecking
  private let fileReader: any DefinitionFileReading

  /// - Parameter schema: The checker for the use-cases schema.
  init(
    fileSystem: any FileSystemReading,
    yamlReader: any YAMLReading,
    technicalFieldChecker: any TechnicalFieldChecking,
    markerBindingChecker: any MarkerBindingChecking,
    schema: any SchemaChecking,
    fileReader: any DefinitionFileReading,
  ) {
    self.fileSystem = fileSystem
    self.yamlReader = yamlReader
    self.technicalFieldChecker = technicalFieldChecker
    self.markerBindingChecker = markerBindingChecker
    self.schema = schema
    self.fileReader = fileReader
  }

  func load(
    at location: URL,
    path: WorkspacePath,
  ) throws(DefinitionFileLoadingError) -> DefinitionFile {
    let text: String

    do {
      text = try fileSystem.readText(at: location)
    } catch {
      throw .invalid([.unreadableDefinition(path, because: error)])
    }

    let value: AuthoredValue

    do {
      value = try yamlReader.read(
        text,
        file: path.text,
        kind: .useCase,
      )
    } catch {
      throw .invalid([error.diagnostic(in: path)])
    }

    return try definitionFile(
      from: value,
      at: path,
    )
  }

  /// The checks a file's value passes before it is read as use cases: the technical fields, the
  /// markers written as bindings, the schema, and then the use cases themselves.
  func definitionFile(
    from value: AuthoredValue,
    at path: WorkspacePath,
  ) throws(DefinitionFileLoadingError) -> DefinitionFile {
    // A field that names code or tools is reported in its own words, so the schema's complaint
    // about the same field is dropped: one problem is reported once. Everything else the schema
    // finds is kept, and the file is not read as definitions while it has any.
    let technical = technicalFieldChecker.check(
      value,
      file: path,
    )
    // A binding that says `kind: marker` is reported in its own words too, and the schema's
    // complaints about that same binding are dropped.
    let markers = markerBindingChecker.check(
      value,
      file: path,
    )
    let failures = schema.check(value)

    guard technical.isEmpty, markers.diagnostics.isEmpty, failures.isEmpty else {
      let others = failures.filter { failure in
        (technical.isEmpty || !failure.isOnlyTechnicalFields) && !markers.covers(failure)
      }
      let reported = technical + markers.diagnostics + others.map { failure in
        failure.diagnostic(in: path)
      }

      throw .invalid(reported.sorted())
    }

    do {
      return try fileReader.read(
        value,
        file: path,
      )
    } catch {
      switch error {
      case let .invalid(diagnostics):
        throw .invalid(diagnostics)
      }
    }
  }
}
