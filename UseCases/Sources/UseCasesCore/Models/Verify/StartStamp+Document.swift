extension StartStamp {
  /// The stamp as `start.json` writes it (chapter 12 §11).
  var document: StoreJSONValue {
    .members([
      "start_version": .integer(1),
      "run_id": .string(identifier.text),
      "started_at": .string(startedAt),
      "opened_by": .string(openedBy.rawValue),
      "selected": .strings(selected.map(\.text)),
      "validations_sha256": .string(validationsDigest),
      "routes": .array(
        routes.map { route in
          .members([
            "use_case": .string(route.useCase.text),
            "route": .string(route.route.text),
            "fingerprint": .string(route.fingerprint.text),
          ])
        },
      ),
      "files": .object(
        files.map { file in
          StoreJSONMember(
            key: file.path,
            value: .string(file.digest),
          )
        },
      ),
    ])
  }
}
