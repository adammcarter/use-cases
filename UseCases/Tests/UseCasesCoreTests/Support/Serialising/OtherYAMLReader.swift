import Testing
@testable import UseCasesCore

/// A YAML reader that is not ours, run with a script that reads every written text and says where
/// its value differs from the one written.
enum OtherYAMLReader: String, CustomTestStringConvertible {
  /// PyYAML, which reads YAML 1.1, run by `uv`.
  case pyyaml

  /// ruamel.yaml, which reads YAML 1.2, run by `uv`.
  case ruamel

  /// Ruby's Psych, run by the `ruby` the system has.
  case psych

  /// go-yaml version 2, run by `go`.
  case goyaml2

  /// go-yaml version 3, run by `go`.
  case goyaml3

  static let usingUV: [OtherYAMLReader] = [.pyyaml, .ruamel]

  var testDescription: String {
    rawValue
  }

  static let usingGo: [OtherYAMLReader] = [.goyaml2, .goyaml3]

  /// The files the reader's command needs beside `cases.json`, by name.
  var files: [String: String] {
    switch self {
    case .pyyaml, .ruamel:
      ["read.py": Self.pythonScript]
    case .psych:
      ["read.rb": Self.rubyScript]
    case .goyaml2, .goyaml3:
      ["go.mod": Self.goModule, "main.go": Self.goScript]
    }
  }

  /// The shell command that reads `cases.json` with this reader, or `nil` when what runs it is not
  /// installed.
  var command: String? {
    switch self {
    case .pyyaml, .ruamel:
      InstalledTool.uvProgram.map { program in
        [
          program, "run", "--no-project", "--quiet", "--with",
          self == .pyyaml ? "pyyaml" : "ruamel.yaml",
          "python", "read.py", rawValue, "cases.json",
        ].map(ShellWord.quoting).joined(separator: " ")
      }
    case .psych:
      InstalledTool.rubyProgram.map { program in
        [program, "read.rb", "cases.json"].map(ShellWord.quoting).joined(separator: " ")
      }
    case .goyaml2, .goyaml3:
      InstalledTool.goProgram.map { program in
        // A cold module cache makes `go run` print "go: downloading ..." on the console the test
        // compares. Fetching first, with its output dropped, gives a cold cache the same console
        // as a warm one. A failed fetch is not hidden: `go run` then fails the same way, aloud.
        let fetch = [program, "mod", "download"].map(ShellWord.quoting).joined(separator: " ")
        let run = [program, "run", ".", rawValue, "cases.json"]
          .map(ShellWord.quoting).joined(separator: " ")
        return "export GOFLAGS=-mod=mod; \(fetch) >/dev/null 2>&1; \(run)"
      }
    }
  }

  /// Reads the JSON file of `{"yaml": text, "json": expected}` cases and prints each case whose
  /// value differs, then `OK <number of cases>` when none does.
  private static let pythonScript = """
  import json
  import sys

  reader, path = sys.argv[1], sys.argv[2]

  if reader == "pyyaml":
      import yaml

      def load(text):
          return yaml.safe_load(text)
  else:
      from ruamel.yaml import YAML

      loader = YAML(typ="safe")

      def load(text):
          return loader.load(text)

  with open(path, encoding="utf-8") as handle:
      cases = json.load(handle)

  different = 0

  for index, case in enumerate(cases):
      expected = json.dumps(json.loads(case["json"]), sort_keys=True)
      try:
          got = json.dumps(load(case["yaml"]), sort_keys=True)
      except Exception as error:
          got = "ERROR " + type(error).__name__ + ": " + str(error).replace("\\n", " ")[:150]
      if got != expected:
          different += 1
          if different <= 12:
              shown = json.dumps(case["yaml"])
              print("DIFFERENT", index, shown, "expected", expected[:300], "got", got[:300])

  print("DIFFERENT TOTAL" if different else "OK", different or len(cases))
  """

  private static let rubyScript = """
  require "json"
  require "yaml"

  def canonical(value)
    case value
    when Hash
      sorted = {}
      value.keys.sort.each do |key|
        sorted[key] = canonical(value[key])
      end
      sorted
    when Array
      value.map do |item|
        canonical(item)
      end
    else
      value
    end
  end

  cases = JSON.parse(File.read(ARGV[0]))
  different = 0

  cases.each_with_index do |entry, index|
    expected = JSON.generate(canonical(JSON.parse(entry["json"])))
    begin
      got = JSON.generate(canonical(YAML.safe_load(entry["yaml"])))
    rescue Exception => error
      got = "ERROR " + error.class.to_s + ": " + error.message.tr("\\n", " ")[0, 150]
    end
    next if got == expected
    different += 1
    if different <= 12
      shown = entry["yaml"].inspect
      puts ["DIFFERENT", index, shown, "expected", expected[0, 300], "got", got[0, 300]].join(" ")
    end
  end

  if different > 0
    puts "DIFFERENT TOTAL " + different.to_s
  else
    puts "OK " + cases.length.to_s
  end
  """

  private static let goModule = """
  module readers

  go 1.21

  require (
    gopkg.in/yaml.v2 v2.4.0
    gopkg.in/yaml.v3 v3.0.1
  )

  """

  private static let goScript = """
  package main

  import (
    "encoding/json"
    "fmt"
    "os"

    yamlv2 "gopkg.in/yaml.v2"
    yamlv3 "gopkg.in/yaml.v3"
  )

  type testCase struct {
    YAML string `json:"yaml"`
    JSON string `json:"json"`
  }

  func normalise(value interface{}) interface{} {
    switch typed := value.(type) {
    case map[interface{}]interface{}:
      result := map[string]interface{}{}
      for key, item := range typed {
        name, isText := key.(string)
        if !isText {
          name = fmt.Sprintf("NONSTRING %v", key)
        }
        result[name] = normalise(item)
      }
      return result
    case map[string]interface{}:
      result := map[string]interface{}{}
      for key, item := range typed {
        result[key] = normalise(item)
      }
      return result
    case []interface{}:
      result := []interface{}{}
      for _, item := range typed {
        result = append(result, normalise(item))
      }
      return result
    default:
      return value
    }
  }

  // Decided (chapter 09, YAML11Schema): a lone y, Y, n or N is text. go-yaml version 2 alone
  // reads it as a boolean, so only that difference is allowed for it.
  func looseBoolean(text string) (value bool, isLoose bool) {
    switch text {
    case "y", "Y":
      return true, true
    case "n", "N":
      return false, true
    default:
      return false, false
    }
  }

  func equal(expected interface{}, got interface{}) bool {
    switch want := expected.(type) {
    case string:
      if text, isText := got.(string); isText {
        return text == want
      }
      flag, isBoolean := got.(bool)
      value, isLoose := looseBoolean(want)
      return isBoolean && isLoose && flag == value
    case map[string]interface{}:
      have, isMapping := got.(map[interface{}]interface{})
      if !isMapping || len(have) != len(want) {
        return false
      }
      for key, item := range want {
        found, present := have[key]
        if value, isLoose := looseBoolean(key); !present && isLoose {
          found, present = have[value]
        }
        if !present || !equal(item, found) {
          return false
        }
      }
      return true
    case []interface{}:
      have, isList := got.([]interface{})
      if !isList || len(have) != len(want) {
        return false
      }
      for position, item := range want {
        if !equal(item, have[position]) {
          return false
        }
      }
      return true
    default:
      encodedWant, _ := json.Marshal(expected)
      encodedHave, _ := json.Marshal(normalise(got))
      return string(encodedWant) == string(encodedHave)
    }
  }

  func cut(text string) string {
    if len(text) > 300 {
      return text[:300]
    }
    return text
  }

  func main() {
    reader := os.Args[1]
    data, _ := os.ReadFile(os.Args[2])
    var cases []testCase
    if err := json.Unmarshal(data, &cases); err != nil {
      fmt.Println("CASES UNREADABLE", err)
      return
    }
    different := 0
    for index, entry := range cases {
      var expected interface{}
      _ = json.Unmarshal([]byte(entry.JSON), &expected)
      want, _ := json.Marshal(expected)
      var got interface{}
      var err error
      if reader == "goyaml2" {
        err = yamlv2.Unmarshal([]byte(entry.YAML), &got)
      } else {
        err = yamlv3.Unmarshal([]byte(entry.YAML), &got)
      }
      have := ""
      if err != nil {
        have = "ERROR " + err.Error()
      } else if encoded, failure := json.Marshal(normalise(got)); failure != nil {
        have = "ERROR " + failure.Error()
      } else {
        have = string(encoded)
      }
      allowed := reader == "goyaml2" && err == nil && equal(expected, got)
      if have != string(want) && !allowed {
        different++
        if different <= 12 {
          shown, _ := json.Marshal(entry.YAML)
          fmt.Println("DIFFERENT", index, string(shown), "expected", cut(string(want)),
            "got", cut(have))
        }
      }
    }
    if different > 0 {
      fmt.Println("DIFFERENT TOTAL", different)
    } else {
      fmt.Println("OK", len(cases))
    }
  }
  """
}
