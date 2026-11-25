@testable import UseCasesCore

/// The store samples of `docs/schemas/engine/validate.py`, each with the verdict that script
/// expects.
enum StoreSchemaSamples {
  static let all: [StoreSchemaSample] = runSamples + resultSamples + completionSamples +
    startSamples + runOrderSamples

  static let runSamples: [StoreSchemaSample] = {
    let manifest = StoreSamples.manifest()
    let source = StoreSamples.source

    var samples: [StoreSchemaSample] = [
      .valid("the --run manifest", .run, manifest),
      .valid("a record manifest", .run, StoreSamples.manifest(kind: "record")),
      .valid(
        "a verify manifest where you ran the tests",
        .run,
        manifest.setting(
          "sources",
          """
          [{"id":"auth-tests","report":"reports/auth-tests/auth-tests.jsonl",\
          "transformer":"swift-testing","working_dir":"services/auth"}]
          """,
        ),
      ),
      .valid(
        "a report folder without a name",
        .run,
        manifest.setting("sources", "[\(source.setting("report", "\"reports/auth-tests\"").json)]"),
      ),
      .invalid(
        "an exit code with no command",
        .run,
        manifest.setting("sources", "[\(source.removing("command").json)]"),
      ),
      .invalid(
        "a seconds with no command",
        .run,
        manifest.setting("sources", "[\(source.removing("command").removing("exit_code").json)]"),
      ),
      .invalid("a record manifest with sources", .run, manifest.setting("kind", "\"record\"")),
      .invalid(
        "a route without a use case",
        .run,
        manifest.setting("diagnostics", #"[{"problem":"x","route":"unit-tests"}]"#),
      ),
      .invalid("an unknown kind", .run, manifest.setting("kind", "\"batch\"")),
      .invalid("a kind named after the file check", .run, manifest.setting("kind", "\"validate\"")),
      .invalid("a bad run id", .run, manifest.setting("run_id", "\"12\"")),
      .invalid(
        "the reserved run id",
        .run,
        manifest.setting("run_id", "\"00000000000000000000000000000000\""),
      ),
      .invalid("a bad timestamp", .run, manifest.setting("created_at", "\"yesterday\"")),
      .invalid(
        "a timestamp that is not UTC",
        .run,
        manifest.setting("created_at", "\"2026-09-25T12:34:56+01:00\""),
      ),
      .invalid("no notes", .run, manifest.removing("notes")),
      .invalid("an unknown member", .run, manifest.setting("something_new", "{}")),
      .invalid("an empty error", .run, manifest.setting("errors", #"[""]"#)),
    ]
    for (name, report) in [
      ("a project path", ".build/use-cases/auth-tests.jsonl"),
      ("outside reports/", "outputs/auth-tests/x"),
      ("escaping", "reports/auth-tests/../../run.json"),
    ] {
      samples.append(.invalid(
        "a report that is \(name)",
        .run,
        manifest.setting("sources", "[\(source.setting("report", "\"\(report)\"").json)]"),
      ))
    }
    samples.append(.invalid(
      "a report start time",
      .run,
      manifest.setting("sources", "[\(source.setting("report_started_at", "1790180980.2").json)]"),
    ))

    return samples
  }()

  static let resultSamples: [StoreSchemaSample] = {
    let result = StoreSamples.result()

    return [
      .valid("a route result", .result, result),
      .valid("a recorded result", .result, StoreSamples.recordedResult()),
      .valid(
        "a result with an attachment",
        .result,
        result.setting(
          "attachments",
          """
          [{"name":"log.txt","blob":"uc-blob-v1-sha256:\(StoreSamples.digest("1"))",\
          "size_bytes":9,"media_type":"text/plain"}]
          """,
        ),
      ),
      .valid(
        "a fingerprint of another format",
        .result,
        result.setting("fingerprint", "\"uc-route-v2-blake3:abc\""),
      ),
      .invalid("an unknown status", .result, result.setting("status", "\"skipped\"")),
      .invalid("an empty via", .result, result.setting("via", "[]")),
      .invalid("a bad fingerprint", .result, result.setting("fingerprint", "\"sha256:x\"")),
      .invalid(
        "a version 1 fingerprint with a short digest",
        .result,
        result.setting("fingerprint", "\"uc-route-v1-sha256:abc\""),
      ),
      .invalid("a verify result without links", .result, result.removing("links")),
      .invalid(
        "a recorded result with links",
        .result,
        StoreSamples.recordedResult().setting("links", "{}"),
      ),
      .invalid("a duplicate via", .result, result.setting("via", #"["a","a"]"#)),
      .invalid("an unknown member", .result, result.setting("confidence", "0.9")),
      .invalid(
        "a blob that is not a digest",
        .result,
        result.setting("attachments", #"[{"name":"x","blob":"sha256:1","size_bytes":1}]"#),
      ),
      .invalid(
        "a size above the safe integers",
        .result,
        result.setting(
          "attachments",
          """
          [{"name":"x","blob":"uc-blob-v1-sha256:\(StoreSamples.digest("1"))",\
          "size_bytes":9007199254740992}]
          """,
        ),
      ),
      .invalid(
        "a link key that is not a key",
        .result,
        result.setting("links", #"{"nope":"pass"}"#),
      ),
    ]
  }()

  static let completionSamples: [StoreSchemaSample] = {
    let completion = StoreSamples.completion()
    let digest = StoreSamples.digest("c")

    return [
      .valid("a completion marker", .completion, completion),
      .valid(
        "a record run's marker",
        .completion,
        completion.setting("outputs_sha256", "{}").setting("reports_sha256", "{}"),
      ),
      .valid(
        "a marker with a start stamp",
        .completion,
        completion.setting("start_sha256", "\"\(StoreSamples.digest("e"))\""),
      ),
      .valid(
        "an interrupted run",
        .completion,
        completion.setting("termination", "\"interrupted\""),
      ),
      .invalid("no outputs digests", .completion, completion.removing("outputs_sha256")),
      .invalid("no reports digests", .completion, completion.removing("reports_sha256")),
      .invalid(
        "a report path that escapes",
        .completion,
        completion.setting("reports_sha256", JSONMembers(["../x": "\"" + digest + "\""]).json),
      ),
      .invalid(
        "an output path that escapes",
        .completion,
        completion.setting("outputs_sha256", JSONMembers(["../x": "\"" + digest + "\""]).json),
      ),
      .invalid(
        "an unknown termination",
        .completion,
        completion.setting("termination", "\"crashed\""),
      ),
      .invalid("a negative result count", .completion, completion.setting("result_count", "-1")),
      .invalid(
        "an upper case digest",
        .completion,
        completion.setting("manifest_sha256", "\"\(String(repeating: "A", count: 64))\""),
      ),
      .invalid("version 2", .completion, completion.setting("completion_version", "2")),
    ]
  }()

  static let startSamples: [StoreSchemaSample] = {
    let start = StoreSamples.start

    return [
      .valid("a start stamp", .start, start),
      .valid("a stamp opened by --run", .start, start.setting("opened_by", "\"run\"")),
      .invalid("no opener", .start, start.removing("opened_by")),
      .invalid("a report time", .start, start.setting("report_started_at", "1790180980.2")),
      .invalid("no routes", .start, start.removing("routes")),
      .invalid("an unknown opener", .start, start.setting("opened_by", "\"ci\"")),
      .invalid(
        "an absolute file",
        .start,
        start.setting(
          "files",
          JSONMembers(["/etc/passwd": StoreSamples.quoted(StoreSamples.digest("f"))]).json,
        ),
      ),
      .invalid("a bad digest", .start, start.setting("files", #"{"a.swift":"xyz"}"#)),
    ]
  }()

  static let runOrderSamples: [StoreSchemaSample] = [
    .valid("a high-water mark", .runOrder, StoreSamples.runOrder),
    .invalid("version 2", .runOrder, StoreSamples.runOrder.setting("order_version", "2")),
    .invalid("an unknown member", .runOrder, StoreSamples.runOrder.setting("extra", "1")),
    .invalid("no last run", .runOrder, StoreSamples.runOrder.removing("last_run_id")),
  ]
}
