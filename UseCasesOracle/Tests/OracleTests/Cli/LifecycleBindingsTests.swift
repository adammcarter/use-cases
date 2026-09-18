import Foundation
import Testing

//: @use-case:lifecycle.bindings.rebind_repoints_a_binding#blackbox
/// The black-box oracle for lifecycle/bindings.yml, row
/// `rebind_repoints_a_binding`.
struct LifecycleRebindTests {
  // golden_same_file. A marker on a declaration that cannot fail when its claim
  // does reads as proven from every angle the tool reports on. Being unable to
  // move it is the worst state a matrix can hold.
  @Test
  func `the marker moves and the registration moves with it, appended`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    let before = try BindingsWorkspace.registryLineCount(directory)

    let moved = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 5,
      end: 7,
    )
    #expect(moved.isOk == true, Comment(rawValue: moved.standardError))
    #expect(moved.data.at("moved_from.start_line")?.intValue == 1)
    // A release AND a re-registration: the ledger is only ever appended to.
    #expect(moved.data["registry_events_appended"]?.intValue == 2)
    #expect(try BindingsWorkspace.registryLineCount(directory) == before + 2)
    #expect(try BindingsWorkspace.markerLines(directory, file: "src/alpha.ts").count == 2)
  }

  // golden_across_files.
  @Test
  func `a binding moves between files, leaving no marker behind`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha", "beta"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )

    let moved = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/beta.ts",
      start: 1,
      end: 3,
    )
    #expect(moved.isOk == true)
    #expect(
      try BindingsWorkspace.markerLines(directory, file: "src/alpha.ts").isEmpty,
      "the old file keeps nothing",
    )
    #expect(try BindingsWorkspace.markerLines(directory, file: "src/beta.ts").count == 2)
  }

  // bad_unresolvable_target. A rebind that cannot succeed changes NOTHING —
  // half-moving a binding would be worse than refusing.
  @Test
  func `a target that cannot resolve leaves source and ledger untouched`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    let linesBefore = try BindingsWorkspace.registryLineCount(directory)
    let sourceBefore = try directory.readFile("src/alpha.ts")

    let moved = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 900,
      end: 902,
    )
    #expect(moved.isOk == false)
    #expect(BindingsWorkspace.errorCodes(moved).contains("BIND_SPAN_OUT_OF_RANGE"))
    #expect(try BindingsWorkspace.registryLineCount(directory) == linesBefore)
    #expect(try directory.readFile("src/alpha.ts") == sourceBefore)
  }

  // bad_unbound_row_is_refused. The refusal names the command that would work.
  @Test
  func `rebinding a row that was never bound is refused and points at bind`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    let moved = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )

    #expect(moved.isOk == false)
    #expect(BindingsWorkspace.errorCodes(moved).contains("NOT_REGISTERED"))
    #expect(moved.data.encoded.contains("use-cases bind"), "the refusal names bind")
  }

  // edge_verified_local_does_not_survive_the_move. A moved binding never
  // inherits the proof of the one it replaced.
  @Test
  func `VERIFIED_LOCAL does not survive a rebind, and re-verifying restores it`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    _ = try await BindingsWorkspace.run(directory, ["verify", "--row", "probe.core.alpha"])
    let verified = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    #expect(verified?["local_status"]?.stringValue == "VERIFIED_LOCAL")

    _ = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 5,
      end: 7,
    )
    let moved = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    #expect(moved?["local_status"]?.stringValue == "STALE_LOCAL")

    _ = try await BindingsWorkspace.run(directory, ["verify", "--row", "probe.core.alpha"])
    let reverified = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    #expect(reverified?["local_status"]?.stringValue == "VERIFIED_LOCAL")
  }

  // edge_suffixed_binding_moves_alone.
  @Test
  func `a row with two suffixed bindings moves only the one named`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
      suffix: "one",
    )
    let second = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 7,
      end: 9,
      suffix: "two",
    )
    #expect(second.isOk == true, Comment(rawValue: second.standardError))

    let moved = try await BindingsWorkspace.rebind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 9,
      end: 11,
      suffix: "two",
    )
    #expect(moved.isOk == true)

    let lines = try BindingsWorkspace.markerLines(directory, file: "src/alpha.ts")
    let one = lines.filter { line in
      line.contains("#one")
    }
    let two = lines.filter { line in
      line.contains("#two")
    }
    #expect(one.count == 2, "#one must not have moved")
    #expect(two.count == 2)
  }
}

//: @use-case:end lifecycle.bindings.rebind_repoints_a_binding#blackbox

//: @use-case:lifecycle.bindings.unbind_releases_a_registration#blackbox
/// The black-box oracle for lifecycle/bindings.yml, row
/// `unbind_releases_a_registration`.
struct LifecycleUnbindTests {
  // golden_clean. Removing a marker by hand never released its registration, so
  // a retired behaviour stayed registered forever and its slug could never be
  // bound again. This is that exit.
  @Test
  func `the marker goes, the registration is released, and the slug rebinds`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )

    let released = try await BindingsWorkspace.unbind(directory, row: "alpha")
    #expect(released.isOk == true)
    #expect(try BindingsWorkspace.markerLines(directory, file: "src/alpha.ts").isEmpty)

    let again = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 5,
      end: 7,
    )
    #expect(
      again.isOk == true,
      "the same slug must bind again with no duplicate error",
    )
    #expect(!BindingsWorkspace.errorCodes(again).contains("DUPLICATE_REGISTRATION"))
  }

  // bad_unregistered_slug_is_refused.
  @Test
  func `releasing a slug that is not registered is refused and writes nothing`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    let before = try BindingsWorkspace.registryLineCount(directory)

    let released = try await BindingsWorkspace.unbind(
      directory,
      row: "alpha",
      extra: ["--suffix", "nothing-here"],
    )
    #expect(released.isOk == false)
    #expect(try BindingsWorkspace.registryLineCount(directory) == before)
  }

  // edge_already_stripped_by_hand. Hand-editing the source must never strand a
  // registration with no supported way out.
  @Test
  func `a registration whose markers were removed by hand is still releasable`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )

    let stripped = try directory.readFile("src/alpha.ts")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .filter { line in
        !line.contains("@use-case:")
      }
      .joined(separator: "\n")
    try directory.writeFile("src/alpha.ts", contents: stripped)

    let released = try await BindingsWorkspace.unbind(directory, row: "alpha")
    #expect(released.isOk == true, "a stripped source must still release")
  }

  // edge_dry_run_touches_nothing.
  @Test
  func `a dry run reports the release without touching source or registry`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    let before = try BindingsWorkspace.registryLineCount(directory)

    let preview = try await BindingsWorkspace.unbind(
      directory,
      row: "alpha",
      extra: ["--dry-run"],
    )
    #expect(preview.isOk == true)
    #expect(preview.data["registry_event_appended"]?.boolValue == false)
    #expect(
      try BindingsWorkspace.markerLines(directory, file: "src/alpha.ts").count == 2,
      "the markers must still be there",
    )
    #expect(try BindingsWorkspace.registryLineCount(directory) == before)
  }

  // edge_leaves_nothing_claiming_verified.
  @Test
  func `unbinding leaves nothing behind claiming the row is verified`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    _ = try await BindingsWorkspace.run(directory, ["verify", "--row", "probe.core.alpha"])
    let verified = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    #expect(verified?["local_status"]?.stringValue == "VERIFIED_LOCAL")

    _ = try await BindingsWorkspace.unbind(directory, row: "alpha")
    let row = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    #expect(row?["status"]?.stringValue == "UNBOUND")
    #expect(
      row?["local_status"]?.isNull == true,
      "an unbound row claims no local proof",
    )
  }

  // edge_one_suffixed_binding_of_two.
  @Test
  func `releasing one suffixed binding leaves the other registered`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
      suffix: "one",
    )
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 7,
      end: 9,
      suffix: "two",
    )

    let released = try await BindingsWorkspace.unbind(
      directory,
      row: "alpha",
      extra: ["--suffix", "one"],
    )
    #expect(released.isOk == true)
    let row = try await BindingsWorkspace.scannedRow(directory, row: "alpha")
    let slugs = (row?["current_binding_slugs"]?.arrayValue ?? []).compactMap { slug in
      slug.stringValue
    }
    #expect(slugs == ["probe.core.alpha#two"])
  }
}

//: @use-case:end lifecycle.bindings.unbind_releases_a_registration#blackbox

//: @use-case:lifecycle.bindings.retired_row_can_leave_the_matrix#blackbox
/// The black-box oracle for lifecycle/bindings.yml, row
/// `retired_row_can_leave_the_matrix`.
struct LifecycleRetiredRowTests {
  // golden_retire. A retired behaviour must leave no permanent integrity error.
  @Test
  func `a released binding whose row has left the matrix scans clean`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha", "beta"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )

    _ = try await BindingsWorkspace.unbind(directory, row: "alpha")
    try BindingsWorkspace.deleteRow(directory, row: "alpha")

    let scanned = try await BindingsWorkspace.scan(directory)
    #expect(BindingsWorkspace.integrityCodes(scanned).isEmpty)
  }

  // bad_still_bound_row_missing. Deleting the row WITHOUT releasing it first is
  // still an error, and the remediation names the supported way out rather than
  // telling anyone to edit the ledger.
  @Test
  func `a row still bound but missing from the matrix is reported`() async throws {
    let directory = try BindingsWorkspace.make(rows: ["alpha", "beta"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    try BindingsWorkspace.deleteRow(directory, row: "alpha")

    let scanned = try await BindingsWorkspace.run(directory, ["scan"])
    let codes = BindingsWorkspace.integrityCodes(scanned.data)
    #expect(codes.contains("REGISTRY_ROW_MISSING"))
    #expect(
      scanned.data.encoded.contains("unbind"),
      "the cure is unbind, not a ledger edit",
    )
  }

  // edge_released_slug_with_no_marker. A release is not an absence: a slug that
  // was properly released must not then be reported as a missing marker.
  @Test
  func `a released slug with no marker left is not reported as missing`()
    async throws
  {
    let directory = try BindingsWorkspace.make(rows: ["alpha", "beta"])
    _ = try await BindingsWorkspace.bind(
      directory,
      row: "alpha",
      file: "src/alpha.ts",
      start: 1,
      end: 3,
    )
    _ = try await BindingsWorkspace.unbind(directory, row: "alpha")

    let codes = try await BindingsWorkspace.integrityCodes(BindingsWorkspace.scan(directory))
    #expect(!codes.contains("MISSING_MARKER"))
    #expect(!codes.contains("REGISTRY_ROW_MISSING"))
  }
}

//: @use-case:end lifecycle.bindings.retired_row_can_leave_the_matrix#blackbox
