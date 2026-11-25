extension VerdictRecorder {
  /// The item whose id is exactly `target`; otherwise the one item whose id starts with it. An
  /// exact id always wins over a prefix, as for every target on the command line (chapter 16 §9).
  static func match<Item>(
    _ target: String,
    among items: [Item],
    by identifier: (Item) -> String,
  ) -> PrefixMatch<Item> {
    let exact = items.first { item in
      identifier(item).isExactlyEqual(to: target)
    }

    if let exact {
      return .found(exact)
    }

    let prefix = Array(target.utf8)
    let starting = items.filter { item in
      identifier(item).utf8.starts(with: prefix)
    }

    guard let first = starting.first else {
      return .none
    }
    guard starting.count > 1 else {
      return .found(first)
    }

    return .several(
      starting.map(identifier).sorted { lhs, rhs in
        lhs.precedesExactly(rhs)
      },
    )
  }
}
