import MCP

/// Makes a published schema stand alone (chapter 20 §4): every `$ref`, to another file or to
/// somewhere in the same one, is replaced by a copy of what it points at, and the `$id`, `$defs`
/// and nested `$schema` that only the references used are dropped. What is left needs no other
/// file and no base address, for any host.
struct SchemaInliner {
  private static let dialect = "https://json-schema.org/draft/2020-12/schema"

  /// Keywords that only name or hold what a `$ref` points at.
  private static let dropped: Set = ["$id", "$schema", "$defs"]

  /// Keywords whose members are named schemas, not keywords: a property called `$id` is a
  /// property.
  private static let schemaMaps: Set = [
    "properties", "patternProperties", "dependentSchemas",
  ]

  /// The schemas by file name, as `$ref`s write it at the end of their path.
  private let documents: [String: Value]

  init(documents: [String: Value]) {
    self.documents = documents
  }

  /// The schema of `file` with every reference copied in.
  func inlined(_ file: String) throws(SchemaInliningError) -> Value {
    guard let root = documents[file] else {
      throw .missingDocument(file)
    }

    let schema = try expanded(
      root,
      in: file,
      following: [],
    )

    guard case var .object(members) = schema else {
      return schema
    }

    members["$schema"] = .string(Self.dialect)

    return .object(members)
  }

  private func expanded(
    _ value: Value,
    in file: String,
    following: [String],
  ) throws(SchemaInliningError) -> Value {
    switch value {
    case let .object(members):
      return try expandedSchema(
        members,
        in: file,
        following: following,
      )
    case let .array(items):
      var expandedItems: [Value] = []
      for item in items {
        try expandedItems.append(
          expanded(
            item,
            in: file,
            following: following,
          ),
        )
      }

      return .array(expandedItems)
    default:
      return value
    }
  }

  private func expandedSchema(
    _ members: [String: Value],
    in file: String,
    following: [String],
  ) throws(SchemaInliningError) -> Value {
    var kept: [String: Value] = [:]

    for (keyword, member) in members where !Self.dropped.contains(keyword) && keyword != "$ref" {
      if Self.schemaMaps.contains(keyword), case let .object(named) = member {
        var expandedMap: [String: Value] = [:]
        for (name, schema) in named {
          expandedMap[name] = try expanded(
            schema,
            in: file,
            following: following,
          )
        }
        kept[keyword] = .object(expandedMap)
      } else {
        kept[keyword] = try expanded(
          member,
          in: file,
          following: following,
        )
      }
    }

    guard case let .string(reference)? = members["$ref"] else {
      return .object(kept)
    }

    let target = try followed(
      reference,
      from: file,
      following: following,
    )

    // What stands beside a `$ref` says more about the same place, so it wins.
    guard case let .object(targetMembers) = target else {
      return target
    }

    return .object(
      targetMembers.merging(kept) { _, beside in
        beside
      },
    )
  }

  private func followed(
    _ reference: String,
    from file: String,
    following: [String],
  ) throws(SchemaInliningError) -> Value {
    let parts = reference.split(
      separator: "#",
      maxSplits: 1,
      omittingEmptySubsequences: false,
    )
    let path = parts.first.map(String.init) ?? ""
    let pointer = parts.count > 1 ? String(parts[1]) : ""
    let name = path.isEmpty ? file : String(path.split(separator: "/").last ?? "")
    let place = "\(name)#\(pointer)"

    guard !following.contains(place) else {
      throw .circular(place)
    }

    guard let document = documents[name] else {
      throw .missingDocument(name)
    }

    let target = try node(
      at: pointer,
      in: document,
      place: place,
    )

    return try expanded(
      target,
      in: name,
      following: following + [place],
    )
  }

  /// The value a JSON Pointer (RFC 6901) leads to.
  private func node(
    at pointer: String,
    in document: Value,
    place: String,
  ) throws(SchemaInliningError) -> Value {
    var current = document

    for token in pointer.split(separator: "/", omittingEmptySubsequences: true) {
      let key = token.replacingOccurrences(of: "~1", with: "/")
        .replacingOccurrences(of: "~0", with: "~")

      switch current {
      case let .object(members):
        guard let next = members[key] else {
          throw .unresolvedPointer(place)
        }
        current = next
      case let .array(items):
        guard let index = Int(key), items.indices.contains(index) else {
          throw .unresolvedPointer(place)
        }
        current = items[index]
      default:
        throw .unresolvedPointer(place)
      }
    }

    return current
  }
}
