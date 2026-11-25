/// One run of compiling a schema: the nodes made so far, and the definitions a `$ref` can name.
struct SchemaCompilation {
  typealias Keywords = [String: AuthoredValue]

  /// A definition by the document it is in (empty for the schema itself) and its name.
  private struct DefinitionKey: Hashable {
    let document: String
    let name: ExactText
  }

  private(set) var nodes: [SchemaNode] = []
  private var definitions: [DefinitionKey: Int] = [:]

  /// The other schemas a `$ref` may name, by the file name it writes.
  private let documents: [String: AuthoredValue]

  /// The document being compiled: a `$ref` written without a file name means this one.
  private var currentDocument = ""

  /// Whether `additionalProperties: false` refuses an unlisted member.
  private let unknownMembers: UnknownMembers

  init(
    documents: [String: AuthoredValue] = [:],
    unknownMembers: UnknownMembers = .refuse,
  ) {
    self.documents = documents
    self.unknownMembers = unknownMembers
  }

  /// `true` when an unlisted member is to be ignored.
  var ignoresUnknownMembers: Bool {
    switch unknownMembers {
    case .ignore: true
    case .refuse: false
    }
  }

  mutating func compile(_ schema: AuthoredValue) throws(SchemaCompilerError) -> SchemaProgram {
    guard case let .object(members) = schema else {
      throw .notASchema(location: "")
    }

    let keywords = Self.keywords(of: members)
    try checkDialect(keywords["$schema"])

    let definitionSchemas = try object(
      "$defs",
      in: keywords,
      location: [],
    )
    for member in definitionSchemas {
      definitions[DefinitionKey(document: "", name: ExactText(member.key))] = reserveNode()
    }

    let root = reserveNode()
    for member in definitionSchemas {
      try compile(
        member.value,
        into: definitions[DefinitionKey(document: "", name: ExactText(member.key))] ?? root,
        location: ["$defs", member.key],
        isRoot: false,
      )
    }
    try compile(
      schema,
      into: root,
      location: [],
      isRoot: true,
    )

    return SchemaProgram(
      nodes: nodes,
      root: root,
    )
  }

  /// Compiles the schema found at `location` and returns the index of its node.
  mutating func compileSubschema(
    _ schema: AuthoredValue,
    location: [String],
  ) throws(SchemaCompilerError) -> Int {
    let index = reserveNode()
    try compile(
      schema,
      into: index,
      location: location,
      isRoot: false,
    )

    return index
  }

  /// The node of the definition a `$ref` names: `#/$defs/<name>` in the document the `$ref` is
  /// written in, or `<file>#/$defs/<name>` in one of the other documents. A definition of
  /// another document is compiled when first named, so only what a schema uses is compiled.
  mutating func resolve(reference: String) throws(SchemaCompilerError) -> Int {
    let prefix = "/$defs/"
    guard
      let hash = reference.firstIndex(of: "#"),
      reference[reference.index(after: hash)...].hasPrefix(prefix)
    else {
      throw .unresolvedReference(reference)
    }

    let file = String(reference[..<hash])
    let name = String(reference[reference.index(after: hash)...].dropFirst(prefix.count))
    let document = file.isEmpty ? currentDocument : file
    let key = DefinitionKey(
      document: document,
      name: ExactText(name),
    )

    if let index = definitions[key] {
      return index
    }
    guard
      !document.isEmpty,
      case let .object(root)? = documents[document],
      case let .object(definitionSchemas)? = Self.keywords(of: root)["$defs"],
      let schema = definitionSchemas.first(where: { member in
        ExactText(member.key) == key.name
      })?.value
    else {
      throw .unresolvedReference(reference)
    }

    let index = reserveNode()
    definitions[key] = index
    try compileDefinition(
      schema,
      into: index,
      document: document,
      name: name,
    )

    return index
  }

  private mutating func compileDefinition(
    _ schema: AuthoredValue,
    into index: Int,
    document: String,
    name: String,
  ) throws(SchemaCompilerError) {
    let outer = currentDocument
    currentDocument = document
    defer {
      currentDocument = outer
    }

    try compile(
      schema,
      into: index,
      location: [document, "$defs", name],
      isRoot: false,
    )
  }

  private mutating func compile(
    _ schema: AuthoredValue,
    into index: Int,
    location: [String],
    isRoot: Bool,
  ) throws(SchemaCompilerError) {
    switch schema {
    case let .boolean(isAlwaysValid):
      nodes[index].rejectsEverything = !isAlwaysValid
    case let .object(members):
      nodes[index] = try makeNode(
        keywords: Self.keywords(of: members),
        location: location,
        isRoot: isRoot,
      )
    default:
      throw .notASchema(location: Self.text(of: location))
    }
  }

  private mutating func reserveNode() -> Int {
    nodes.append(SchemaNode())

    return nodes.count - 1
  }

  private func checkDialect(_ dialect: AuthoredValue?) throws(SchemaCompilerError) {
    guard case let .string(uri) = dialect, uri != Self.dialect else {
      return
    }

    throw .unsupportedDialect(uri)
  }

  private static let dialect = "https://json-schema.org/draft/2020-12/schema"

  /// The members by keyword; a keyword written twice keeps its last value.
  static func keywords(of members: [AuthoredMember]) -> Keywords {
    var keywords: Keywords = [:]
    for member in members {
      keywords[member.key] = member.value
    }

    return keywords
  }

  static func text(of location: [String]) -> String {
    location.joined(separator: "/")
  }
}
