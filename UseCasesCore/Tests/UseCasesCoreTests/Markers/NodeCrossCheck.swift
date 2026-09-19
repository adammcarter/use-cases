import Foundation
import Testing

/// Runs node's own `crypto` over Swift-made keys and signatures, so the
/// Swift-to-node direction of ed25519 interoperability is proven by node
/// itself rather than inferred.
///
/// This spawns a real `node`. The TypeScript is the oracle for the whole
/// rewrite and node is present wherever the corpus can be regenerated; when it
/// is missing, the test fails rather than passing unproven.
enum NodeCrossCheck {
  struct Case {
    let payload: String
    let signature: String
    let publicKeyPEM: String
    let privateKeyPEM: String
  }

  struct Verdict {
    /// node's `crypto.verify(null, payload, publicKeyPEM, signature)`.
    let nodeVerifiedSwiftSignature: Bool
    /// node's `crypto.sign(null, payload, privateKeyPEM)`, base64.
    let nodeSignature: String
  }

  private static let script = """
  const crypto = require("node:crypto");
  const fs = require("node:fs");
  {
    const cases = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = cases.map((c) => ({
      verified: crypto.verify(
        null,
        Buffer.from(c.payload, "utf8"),
        crypto.createPublicKey(c.public_key_pem),
        Buffer.from(c.signature, "base64")
      ),
      signature: crypto
        .sign(null, Buffer.from(c.payload, "utf8"), crypto.createPrivateKey(c.private_key_pem))
        .toString("base64")
    }));
    process.stdout.write(JSON.stringify(out));
  }
  """

  static func nodeExecutable() throws -> URL {
    let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
    let candidates = pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    let found = candidates
      .map { directory in
        URL(fileURLWithPath: directory).appendingPathComponent("node")
      }
      .first { candidate in
        FileManager.default.isExecutableFile(atPath: candidate.path)
      }
    return try #require(found, "node is required to cross-verify signatures")
  }

  static func run(_ cases: [Case]) throws -> [Verdict] {
    let input = try JSONSerialization.data(withJSONObject: cases.map { check in
      [
        "payload": check.payload,
        "signature": check.signature,
        "public_key_pem": check.publicKeyPEM,
        "private_key_pem": check.privateKeyPEM,
      ]
    })
    let output = try runNode(input: input)
    let decoded = try #require(
      JSONSerialization.jsonObject(with: output) as? [[String: Any]],
      "node printed \(String(bytes: output, encoding: .utf8) ?? "<not UTF-8>")",
    )
    return try decoded.map { entry in
      try Verdict(
        nodeVerifiedSwiftSignature: #require(entry["verified"] as? Bool),
        nodeSignature: #require(entry["signature"] as? String),
      )
    }
  }

  /// The input travels in a file, not on stdin: a node that fails early would
  /// otherwise close the pipe mid-write and SIGPIPE the whole test process.
  private static func runNode(input: Data) throws -> Data {
    let inputFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-node-cross-check-\(UUID().uuidString).json")
    try input.write(to: inputFile)
    defer {
      try? FileManager.default.removeItem(at: inputFile)
    }
    let process = Process()
    process.executableURL = try nodeExecutable()
    process.arguments = ["-e", script, inputFile.path]
    let standardOutput = Pipe()
    process.standardOutput = standardOutput
    try process.run()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, "node exited \(process.terminationStatus)")
    return output
  }
}
