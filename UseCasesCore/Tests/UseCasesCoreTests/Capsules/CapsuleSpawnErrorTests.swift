import Testing
@testable import UseCasesCore

/// node's refusals of a spawn request, measured from node 26's `spawnSync`.
struct CapsuleSpawnErrorTests {
  @Test(arguments: [
    (
      "a\u{0}",
      ["b\u{0}"],
      "/tmp\u{0}",
      1.5,
      "The argument 'file' must be a string without null bytes. Received 'a\\x00'",
    ),
    (
      "true",
      ["ok", "b\u{0}"],
      "/tmp\u{0}",
      1.5,
      "The argument 'args[1]' must be a string without null bytes. Received 'b\\x00'",
    ),
    (
      "true",
      ["it's\u{0}"],
      "/tmp",
      30000,
      "The argument 'args[0]' must be a string without null bytes. Received \"it's\\x00\"",
    ),
    (
      "true",
      [],
      "/tmp\u{0}",
      1.5,
      "The property 'options.cwd' must be a string, Uint8Array, or URL without null bytes. "
        + "Received '/tmp\\x00'",
    ),
    (
      "true",
      [],
      "/tmp",
      1.5,
      #"The value of "timeout" is out of range. It must be an integer. Received 1.5"#,
    ),
  ])
  func `node's argument checks refuse the request in its order`(
    executable: String,
    arguments: [String],
    workingDirectory: String,
    timeout: Double,
    message: String,
  ) throws {
    let request = CapsuleSpawnRequest(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: ["PATH=/usr/bin:/bin"],
      timeoutMilliseconds: timeout,
    )

    var refusal: CapsuleSpawnError?
    do throws(CapsuleSpawnError) {
      _ = try CapsuleProcessSpawner().spawn(request)
    } catch {
      refusal = error
    }

    #expect(refusal?.message == message)
  }

  @Test
  func `a long refused value is cut after 128 characters`() {
    let nul = "\u{0}"
    let value = String(repeating: "v", count: 200) + nul
    let error = CapsuleSpawnError.nullByteInArgument(argument: "args[0]", value: value)

    #expect(
      error.message == "The argument 'args[0]' must be a string without null bytes. Received '"
        + String(repeating: "v", count: 127) + "...",
    )
  }
}
