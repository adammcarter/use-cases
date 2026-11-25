import Foundation
import Testing
@testable import UseCasesTransformers

struct TransformerProgramTests {
  private let program = TransformerProgram()

  private func request(
    in folder: TemporaryFolder,
    extra: String = "",
  ) throws -> String {
    try folder.write(
      "code/tests/a.py",
      "import x\n\ndef test_a():\n    pass\n",
    )
    try folder.write(
      "report.xml",
      JUnitXML.suite(JUnitXML.testCase(
        "a",
        file: "tests/a.py",
        line: "2",
      )),
    )
    try folder.write(
      "request.json",
      """
      {"contract": 1, "job": "results", "use_cases": [], \(extra)
       "links": [{"key": "demo.a#unit-tests.t@tests/a.py:3", "source": "marker",
                  "use_case": "demo.a", "route": "unit-tests", "binding": "t",
                  "role": "validation", "file": "tests/a.py", "range": {"start": 3, "end": 4}}],
       "output": {"report_path": "\(folder.absolute("report.xml"))", "exit_code": null,
                  "working_dir": "."},
       "code_root": "\(folder.absolute("code"))",
       "settings": {"find": "file-line", "line_base": 0}}
      """,
    )

    return folder.absolute("request.json")
  }

  @Test
  func `a results job reads the request and writes the response`() throws {
    let folder = try TemporaryFolder()
    let requestPath = try request(in: folder)
    let responsePath = folder.absolute("response.json")

    let outcome = program.run(arguments: ["junit", "results", requestPath, responsePath])

    #expect(outcome == ProgramOutcome(
      exitCode: 0,
      message: nil,
    ))

    let response = try #require(
      JSONSerialization
        .jsonObject(with: Data(contentsOf: URL(fileURLWithPath: responsePath))) as? [String: Any],
    )
    let results = try #require(response["results"] as? [[String: Any]])

    #expect(Set(response.keys) == ["contract", "results", "unlinked", "diagnostics"])
    #expect(results.count == 1)
    #expect(results[0]["status"] as? String == "pass")
    #expect(results[0]["link"] as? String == "demo.a#unit-tests.t@tests/a.py:3")
  }

  @Test
  func `the same request gives byte for byte the same response`() throws {
    let folder = try TemporaryFolder()
    let requestPath = try request(in: folder)

    _ = program.run(arguments: ["junit", "results", requestPath, folder.absolute("one.json")])
    _ = program.run(arguments: ["junit", "results", requestPath, folder.absolute("two.json")])

    #expect(
      try Data(contentsOf: URL(fileURLWithPath: folder.absolute("one.json")))
        == Data(contentsOf: URL(fileURLWithPath: folder.absolute("two.json"))),
    )
  }

  @Test
  func `fields a later core adds to the request change nothing`() throws {
    let folder = try TemporaryFolder()
    let plain = try request(in: folder)
    let future = try request(
      in: folder,
      extra: "\"from_the_future\": {\"any\": [1]},",
    )

    _ = program.run(arguments: ["junit", "results", plain, folder.absolute("plain.json")])
    _ = program.run(arguments: ["junit", "results", future, folder.absolute("future.json")])

    #expect(
      try Data(contentsOf: URL(fileURLWithPath: folder.absolute("plain.json")))
        == Data(contentsOf: URL(fileURLWithPath: folder.absolute("future.json"))),
    )
  }

  @Test
  func `a links job works the same way`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "code/test/a.js",
      "test(\"demo.a#core\", f)\n",
    )
    try folder.write(
      "request.json",
      jsonLine(
        [
          "contract": 1,
          "job": "links",
          "use_cases": [["id": "demo.a"]],
          "code_root": folder.absolute("code"),
          "ignore": [String](),
          "settings": [
            "files": "test/**/*.js",
            "pattern": #"test\("(?P<id>[^"]+)""#,
          ],
        ] as [String: Any],
      ),
    )

    let outcome = program.run(
      arguments: [
        "test-names",
        "links",
        folder.absolute("request.json"),
        folder.absolute("response.json"),
      ],
    )
    let response = try #require(
      JSONSerialization
        .jsonObject(with: Data(contentsOf: URL(fileURLWithPath: folder
            .absolute("response.json")))) as? [String: Any],
    )

    #expect(outcome.exitCode == 0)
    #expect((response["links"] as? [Any])?.count == 1)
  }

  @Test
  func `no arguments, or the wrong number, is a usage error`() {
    for arguments in [
      [],
      ["junit"],
      ["junit", "results", "a"],
      ["junit", "results", "a", "b", "c"],
    ] {
      let outcome = program.run(arguments: arguments)

      #expect(outcome.exitCode == 2)
      #expect(outcome.message?.contains("usage: use-cases-transformers") == true)
    }
  }

  @Test
  func `an unknown name is a usage error that names the bundled ones`() {
    let outcome = program.run(arguments: ["pytest", "results", "a", "b"])

    #expect(outcome.exitCode == 2)
    #expect(outcome.message?.contains("unknown transformer 'pytest'") == true)
    #expect(outcome.message?.contains("swift-testing") == true)
  }

  @Test(arguments: [
    ("junit", "links"),
    ("test-names", "results"),
    ("junit", "other"),
    ("junit", "")
  ])
  func `a job the transformer does not do is a usage error`(
    name: String,
    job: String,
  ) {
    let outcome = program.run(arguments: [name, job, "a", "b"])

    #expect(outcome.exitCode == 2)
    #expect(outcome.message?.contains("does not do the \(job) job") == true)
  }

  @Test
  func `an unreadable request exits 1 and names the file`() throws {
    let folder = try TemporaryFolder()
    let missing = folder.absolute("missing.json")

    let outcome = program.run(arguments: ["junit", "results", missing, folder.absolute("out.json")])

    #expect(outcome.exitCode == 1)
    #expect(outcome.message?.contains(missing) == true)
  }

  @Test(arguments: [
    "",
    "not json",
    "[]",
    "{\"contract\": 1}",
    "{\"contract\": \"1\", \"links\": []}",
  ])
  func `a request that is not a request exits 1 and nothing is written`(text: String) throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "request.json",
      text,
    )

    let outcome = program.run(
      arguments: ["junit", "results", folder.absolute("request.json"), folder.absolute("out.json")],
    )

    #expect(outcome.exitCode == 1)
    #expect(!FileManager.default.fileExists(atPath: folder.absolute("out.json")))
  }

  @Test(arguments: [
    "{\"links\": [], \"code_root\": \"/c\"}",
    "{\"contract\": 2, \"links\": []}",
    "{\"contract\": null}",
  ])
  func `a request for another contract than 1 is refused`(text: String) throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "request.json",
      text,
    )

    let outcome = program.run(
      arguments: ["junit", "results", folder.absolute("request.json"), folder.absolute("out.json")],
    )

    #expect(outcome.exitCode == 1)
    #expect(outcome.message?.contains("unsupported contract") == true)
  }

  @Test
  func `a report that is damaged exits 1 and nothing is written`() throws {
    let folder = try TemporaryFolder()
    let requestPath = try request(in: folder)

    try folder.write(
      "report.xml",
      "<testsuite><testcase>",
    )

    let outcome = program.run(arguments: [
      "junit",
      "results",
      requestPath,
      folder.absolute("out.json"),
    ])

    #expect(outcome.exitCode == 1)
    #expect(outcome.message?.contains("report.xml") == true)
    #expect(!FileManager.default.fileExists(atPath: folder.absolute("out.json")))
  }

  @Test
  func `a response that cannot be written exits 1`() throws {
    let folder = try TemporaryFolder()
    let requestPath = try request(in: folder)

    let outcome = program.run(
      arguments: ["junit", "results", requestPath, folder.absolute("no/such/folder/out.json")],
    )

    #expect(outcome.exitCode == 1)
    #expect(outcome.message?.contains("cannot write the response") == true)
  }

  @Test
  func `every message starts with the program's name`() {
    #expect(program.run(arguments: []).message?.hasPrefix("use-cases-transformers: ") == true)
  }
}
