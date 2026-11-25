extension VerifiedRun {
  /// The `--json` document of chapter 16 §11 (`cli-verify.schema.json`) as text: the sealed run's
  /// manifest fields and its results.
  ///
  /// - Parameters:
  ///   - step: `finish` or `run`.
  ///   - outputVersion: The shape version every `--json` document carries (chapter 16 §5).
  public func documentText(
    step: String,
    outputVersion: Int,
  ) -> String {
    let bytes = StoreJSONWriter().pretty(
      document(
        step: step,
        outputVersion: outputVersion,
      ),
    )

    return String(
      bytes: bytes,
      encoding: .utf8,
    ) ?? ""
  }

  func document(
    step: String,
    outputVersion: Int,
  ) -> StoreJSONValue {
    var members = [
      StoreJSONMember(
        key: "output_version",
        value: .integer(outputVersion),
      ),
      StoreJSONMember(
        key: "command",
        value: .string("verify"),
      ),
      StoreJSONMember(
        key: "step",
        value: .string(step),
      ),
    ]

    if let manifest, case let .object(fields) = manifest.document {
      members += fields
    } else {
      members += [
        StoreJSONMember(
          key: "errors",
          value: .array([]),
        ),
        StoreJSONMember(
          key: "diagnostics",
          value: .array([]),
        ),
        StoreJSONMember(
          key: "notes",
          value: .strings(notes),
        ),
      ]
    }

    members.append(
      StoreJSONMember(
        key: "results",
        value: .array(results.compactMap(\.document)),
      ),
    )

    if isCancelled {
      members.append(
        StoreJSONMember(
          key: "cancelled",
          value: .boolean(true),
        ),
      )
    }

    return .object(members)
  }
}
