import Foundation

/// Reads authored input through the readers authored files are read by.
struct AuthoredInputReader: AuthoredInputReading {
  private let fileSystem: any FileSystemReading
  private let standardInput: any StandardInputReading
  private let yaml: any YAMLReading
  private let json: any JSONReading
  private let nesting: any YAMLNestingScanning
  private let limits: YAMLReadingLimits
  private let workingDirectory: URL

  /// - Parameter workingDirectory: Where a relative path is read from.
  init(
    fileSystem: any FileSystemReading = LocalFileSystem(),
    standardInput: any StandardInputReading = StandardInputReader(),
    yaml: any YAMLReading = StrictYAMLReader(),
    json: any JSONReading = JSONReader(),
    nesting: any YAMLNestingScanning = YAMLNestingScanner(),
    limits: YAMLReadingLimits = .standard,
    workingDirectory: URL,
  ) {
    self.fileSystem = fileSystem
    self.standardInput = standardInput
    self.yaml = yaml
    self.json = json
    self.nesting = nesting
    self.limits = limits
    self.workingDirectory = workingDirectory
  }

  func read(_ source: AuthoredInputSource) throws(AuthoredInputError) -> AuthoredInput {
    let text = try text(of: source)

    return try AuthoredInput(
      name: source.name,
      value: value(
        of: text,
        named: source.name,
        as: Self.format(of: source),
      ),
    )
  }

  private func text(of source: AuthoredInputSource) throws(AuthoredInputError) -> String {
    switch source {
    case .standardInput:
      return try standardInput.readText()
    case let .file(path):
      let location = fileSystem.canonicalLocation(of: url(of: path))
      let kind: FileEntryKind?

      do {
        // The path is looked through to what it names: a link to a file is a file.
        kind = try fileSystem.kindOfItem(at: location)
      } catch {
        throw error.input(path: path)
      }

      guard kind == .file else {
        throw .notAFile(path: path)
      }

      do {
        return try fileSystem.readText(at: location)
      } catch {
        throw error.input(path: path)
      }
    }
  }

  private func url(of path: String) -> URL {
    path.hasPrefix("/")
      ? URL(fileURLWithPath: path)
      : workingDirectory.appendingPathComponent(path)
  }

  private func value(
    of text: String,
    named name: String,
    as format: Format,
  ) throws(AuthoredInputError) -> AuthoredValue {
    switch format {
    case .json:
      return try jsonValue(
        of: text,
        named: name,
      )
    case .yaml:
      return try yamlValue(
        of: text,
        named: name,
      )
    case .unknown:
      // YAML reads what JSON does not, such as `{ id: a.b.c }`, and says why when it cannot.
      if Self.startsLikeJSON(text),
         let value = try? jsonValue(
           of: text,
           named: name,
         )
      {
        return value
      }

      return try yamlValue(
        of: text,
        named: name,
      )
    }
  }

  private func yamlValue(
    of text: String,
    named name: String,
  ) throws(AuthoredInputError) -> AuthoredValue {
    do {
      return try yaml.read(
        text,
        file: name,
        kind: .useCase,
      )
    } catch {
      throw .yaml(error)
    }
  }

  /// JSON is YAML written in flow style, so the same scan measures how deep it nests, before a
  /// parser that recurses is let near it.
  private func jsonValue(
    of text: String,
    named name: String,
  ) throws(AuthoredInputError) -> AuthoredValue {
    let body = text.unicodeScalars.first == "\u{FEFF}"
      ? String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
      : text

    if nesting.firstLine(
      deeperThan: limits.nesting,
      in: YAMLSourceText(body),
    ) != nil {
      throw .limitExceeded(
        name: name,
        .nesting(maximum: limits.nesting),
      )
    }

    let value: AuthoredValue

    do {
      value = try json.read(body)
    } catch {
      throw .json(
        name: name,
        error,
      )
    }

    guard !value.hasTextStartingWithByteOrderMark else {
      throw .leadingByteOrderMark(name: name)
    }

    guard value.valueCount <= limits.values else {
      throw .limitExceeded(
        name: name,
        .values(maximum: limits.values),
      )
    }

    return value
  }

  private static func startsLikeJSON(_ text: String) -> Bool {
    let first = text.unicodeScalars.first { scalar in
      scalar != "\u{FEFF}" && !scalar.properties.isWhitespace
    }

    return first == "{" || first == "["
  }

  private static func format(of source: AuthoredInputSource) -> Format {
    guard case let .file(path) = source else {
      return .unknown
    }

    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "json":
      return .json
    case "yml", "yaml":
      return .yaml
    default:
      return .unknown
    }
  }

  private enum Format {
    case json
    case yaml
    case unknown
  }
}

private extension FileSystemError {
  func input(path: String) -> AuthoredInputError {
    switch self {
    case .notFound:
      .notAFile(path: path)
    case .notUTF8:
      .notUTF8(name: path)
    case let .unreadable(_, reason):
      .unreadable(
        path: path,
        reason: reason,
      )
    }
  }
}
