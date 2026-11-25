import Yams

/// What a conversion carries as it walks the nodes of one file.
struct YAMLConversionState {
  var depth = 0
  var seen: Set<YAMLNodeIdentity> = []
  var aliasDepth = 0

  /// How many lists and mappings written on one line the node being read is inside.
  var flowDepth = 0
  var values = 0
  var lastWrittenLine = 1
  var expansionLine = 1
}

extension Node {
  var isCollection: Bool {
    switch self {
    case .sequence, .mapping: true
    case .scalar, .alias: false
    }
  }

  var identity: YAMLNodeIdentity? {
    guard let mark else {
      return nil
    }

    let kind: YAMLNodeIdentity.Kind =
      switch self {
      case .sequence: .sequence
      case .mapping: .mapping
      case .scalar, .alias: .scalar
      }

    return YAMLNodeIdentity(
      kind: kind,
      line: mark.line,
      column: mark.column,
    )
  }
}
