/// What the plan- and capsule-command corpus comparison replaces, and why each
/// value cannot be compared as recorded.
///
/// Masked on BOTH sides:
/// - the epoch milliseconds in a capsule run id derived from the clock. Only
///   `capsule run` without `--idempotency-key` reaches it: the derived key ends
///   in `Date.now()`, and the run id, its event ids and its ledger directory
///   all carry it. Every other case pins the key, so nothing else is masked,
///   and the intent digests of those events do not cover the key;
/// - the message of a `parse_error` diagnostic — the `yaml` package's own
///   wording, which `Schema/YamlParser` words differently (ladder note, row
///   3c1) — and of an `evidence_parse_error`, which is V8's `JSON.parse`
///   wording (rows 3, 4b and 4d);
/// - the `JSON.parse` wording inside a `showcase_plan_file_unreadable`
///   message. The frozen prefix `Presentation plan file could not be read: `
///   is compared, and so is an errno tail (`ENOENT`, `EISDIR`, `EACCES` —
///   node's own text, which `NodeFile` reproduces).
///
/// Nothing else. Plan ids and content hashes are compared byte for byte,
/// because every plan is pinned with `--generated-at`; capsule verdicts,
/// semantic hashes, command output digests and `recorded_at` are compared
/// because the runner's own default pins the timestamp.
///
/// Each pattern lives inside the step that applies it: a regex literal written
/// as a computed property reads to the `single_line_closure_body` rule as a
/// closure doing something on one line.
enum PlanCapsuleMasking {
  static func masked(_ text: String) -> String {
    maskedEpochs(maskedParserWording(text))
  }

  /// A derived capsule idempotency key carries `Date.now()`
  /// (`capsule:<id>:<epoch>:start`), and the slugified run id built from it
  /// carries it too (`run.capsule_<id>_<epoch>_start`). The delimiters are
  /// kept, so only the clock's own digits are replaced.
  private static func maskedEpochs(_ text: String) -> String {
    let epoch = #/[_:][0-9]{13}[_:]/#
    return text.replacing(epoch) { match in
      let value = String(match.output)
      return value.prefix(1) + "<epoch>" + value.suffix(1)
    }
  }

  private static func maskedParserWording(_ text: String) -> String {
    var masked = text
    let diagnostic = #/("code":"(?:evidence_)?parse_error",[^{}]*?"message":")(?:[^"\\]|\\.)*/#
    let human = #/((?:evidence_)?parse_error: )[^\n]*/#
    let planFile = #/(Presentation plan file could not be read: )(?!E[A-Z]+:)(?:[^"\\]|\\.)*/#
    masked = masked.replacing(diagnostic) { match in
      match.output.1 + "<parser message>"
    }
    masked = masked.replacing(human) { match in
      match.output.1 + "<parser message>"
    }
    return masked.replacing(planFile) { match in
      match.output.1 + "<parser message>"
    }
  }
}
