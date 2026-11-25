/// Text of `use-cases-bridge.yml` files for the tests of loading them.
public enum BridgeFileSamples {
  /// A valid file with a link transformer and two validations, one of which runs a command.
  public static let full = """
  schema_version: 1
  links:
    - transformer: test-names
      settings:
        files: "test/**/*.js"
  validations:
    - id: unit-tests
      report: unit.xml
      run: [node, --test, "--test-reporter-destination={report}"]
      working_dir: scripts
      transformer: junit
      settings: { find: pattern }
      timeout_seconds: 900
    - id: style
      transformer: exit-code

  """

  /// A valid file whose validations are all there is to it.
  public static let validationsOnly = """
  schema_version: 1
  validations:
    - id: unit-tests
      report: unit.xml
      run: [node, --test, "--test-reporter-destination={report}"]
      transformer: junit

  """

  /// A file with one validation, which the test changes one line of.
  public static func validation(
    id: String = "unit-tests",
    lines: [String] = [],
    transformer: String = "junit",
  ) -> String {
    let extra = lines.map { line in
      "    \(line)\n"
    }.joined()

    return "schema_version: 1\nvalidations:\n  - id: \(id)\n\(extra)"
      + "    transformer: \(transformer)\n"
  }
}
