/// A JSON object under construction: its members in order, each value as JSON text.
struct JSONMembers: Sendable {
  private let members: [(key: String, json: String)]

  init(_ members: KeyValuePairs<String, String>) {
    var ordered: [(key: String, json: String)] = []
    for member in members {
      ordered.append((key: member.key, json: member.value))
    }
    self.members = ordered
  }

  private init(members: [(key: String, json: String)]) {
    self.members = members
  }

  /// The object as JSON text.
  var json: String {
    var fragments: [String] = []
    for member in members {
      fragments.append("\"\(member.key)\":\(member.json)")
    }

    return Self.leftBrace + fragments.joined(separator: ",") + Self.rightBrace
  }

  private static let leftBrace = "{"
  private static let rightBrace = "}"

  /// The object with a member replaced in its place, or added at the end.
  func setting(
    _ key: String,
    _ json: String,
  ) -> JSONMembers {
    var changed = members
    if let position = changed.firstIndex(where: { $0.key == key }) {
      changed[position].json = json
    } else {
      changed.append((key: key, json: json))
    }

    return JSONMembers(members: changed)
  }

  /// The object without a member.
  func removing(_ key: String) -> JSONMembers {
    JSONMembers(members: members.filter { $0.key != key })
  }
}
