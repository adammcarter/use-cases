// Regenerates `Tests/UseCasesCoreTests/Markers/MarkersGoldenCorpus.swift` by
// running every case below through the REAL TypeScript marker code in
// `packages/core/dist/markers` and recording exactly what it returns.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-corpus.mjs
//
// The TypeScript is the oracle (ADR 0007 decision 8): span hashes and byte
// offsets are written into ledgers, so the Swift port is asserted against
// these bytes, never against a belief about them. The script refuses to run
// against a `dist` older than its `src`, because a stale oracle is a wrong one.
//
// The corpus is emitted as ASCII-only JSON (every non-ASCII code unit escaped
// as \uXXXX), so the Swift source file cannot alter a single input by
// re-encoding or normalizing it.
import { readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const sourceDirectory = join(repositoryRoot, "packages/core/src/markers");
const distDirectory = join(repositoryRoot, "packages/core/dist/markers");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/MarkersGoldenCorpus.swift"
);

const PORTED = [
  "constants",
  "canonicalJson",
  "markerLine",
  "commentPrefix",
  "physicalLines",
  "spanCanon",
  "swiftFuncRecognizer",
  "scanner"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/markers/${name}.js is older than src; rebuild packages/core first`);
  }
}

const markers = await import(join(distDirectory, "index.js"));
const {
  canonicalJson,
  sha256,
  canonicalJsonSha256,
  isValidSlug,
  splitSlug,
  parseMarkerLine,
  fileExtension,
  resolveCommentPrefix,
  splitPhysicalLines,
  lineIndexOfChar,
  normalizeNewlines,
  canonicalizeSpanLines,
  hashSpanLines,
  recognizeSwiftFuncSpan,
  scanFileForMarkers,
  scanFiles,
  formatInferredSwiftSpanReport
} = markers;

const constants = await import(join(distDirectory, "constants.js"));

const lines = (...parts) => parts.join("\n");
const crlf = (...parts) => parts.join("\r\n");

// ---------------------------------------------------------------------------
// canonicalJson / sha256
// ---------------------------------------------------------------------------

// Every input is JSON text: the Swift side parses the same text, so both
// sides canonicalize an identical document.
const canonicalJsonInputs = {
  code_unit_versus_locale_order:
    '{"a":1,"B":2,"\\u00e9":3,"f":4,"_x":5,"\\uffff":6,"\\ud83d\\ude00":7,"a-b":8,"a_b":9}',
  surrogate_pair_sorts_below_last_bmp_unit: '{"\\uffff":1,"\\ud83d\\ude00":2}',
  surrogate_pair_sorts_above_private_use: '{"\\ud83d\\ude00":1,"\\ue000":2}',
  uppercase_before_lowercase: '{"b":1,"B":2,"a":3,"A":4}',
  prefix_sorts_first: '{"ab":1,"a":2,"abc":3,"":4}',
  digits_lexicographic: '{"item10":1,"item9":2,"item1":3}',
  punctuation_by_code_unit: '{"a.b":1,"a-b":2,"a_b":3,"a~b":4,"a/b":5}',
  nested_objects_sort_at_every_depth:
    '{"z":{"y":[{"b":1,"a":2}],"x":null},"a":[3,{"d":true,"c":false}]}',
  array_order_preserved: '[3,1,2,{"b":1,"a":2},[],{}]',
  scalars_null: "null",
  scalars_true: "true",
  scalars_string_escapes: '"quote \\" backslash \\\\ newline \\n tab \\t ctrl \\u0001 del \\u007f"',
  scalars_line_separator: '"a\\u2028b\\u2029c"',
  numbers: '{"int":1,"neg":-5,"frac":1.5,"big":1e21,"small":1e-7,"zero":0,"negzero":-0,"sum":0.30000000000000004}',
  unicode_values_unescaped: '{"k":"\\u00e9\\ud83d\\ude00"}',
  decomposed_accent_key_sorts_as_base_letter: '{"f":1,"e\\u0301":2,"e":3}',
  empty_object: "{}",
  empty_array: "[]"
};

const canonicalJsonCases = Object.entries(canonicalJsonInputs).map(([name, input]) => ({
  name,
  input,
  canonical: canonicalJson(JSON.parse(input)),
  sha256: canonicalJsonSha256(JSON.parse(input))
}));

const sha256Inputs = {
  empty: "",
  ascii: "abc",
  multibyte: "\u00e9",
  four_byte: "\ud83d\ude00",
  crlf: "a\r\nb",
  canonical_body: "func computeTax() -> Int {\n    return 42\n}\n"
};

const sha256Cases = Object.entries(sha256Inputs).map(([name, input]) => ({
  name,
  input,
  sha256: sha256(input),
  bytes_sha256: sha256(Buffer.from(input, "utf8"))
}));

// ---------------------------------------------------------------------------
// physical lines
// ---------------------------------------------------------------------------

const physicalLineInputs = {
  empty: "",
  single_no_terminator: "a",
  single_lf: "a\n",
  two_no_trailing: "a\nb",
  crlf_trailing: "a\r\nb\r\n",
  cr_only: "a\rb",
  blank_lines_only: "\n\n",
  lone_crlf: "\r\n",
  cr_then_crlf_then_lf: "\r\r\n\n",
  trailing_cr: "x\r",
  multibyte_accent: "caf\u00e9\nx",
  four_byte_emoji_crlf: "\u00e9\n\ud83d\ude00x\r\ny",
  emoji_no_trailing_newline: "a\n\ud83d\ude00\ud83d\ude00",
  line_separator_is_not_a_terminator: "a\u2028b\nc",
  interior_blank_crlf: "a\r\n\r\nb",
  tabs_and_spaces: "\t a \t\n  "
};

const physicalLineCases = Object.entries(physicalLineInputs).map(([name, content]) => {
  const split = splitPhysicalLines(content);
  const positions = [];
  for (let position = -1; position <= content.length + 1; position += 1) {
    positions.push({ position, line_index: lineIndexOfChar(split, position) });
  }
  return { name, content, lines: split, line_index_of_char: positions };
});

// ---------------------------------------------------------------------------
// span canonicalizer
// ---------------------------------------------------------------------------

const spanCanonInputs = {
  empty: [],
  blank_only: ["", "   ", "\t\t"],
  trailing_whitespace_stripped: ["  keep_indent()  ", "", "\ttabbed\t"],
  common_indent_removed: ["    function total() {", "      return sum", "    }"],
  relative_indent_kept: ["if ready:", "  save()", "    notify()"],
  blank_runs_collapsed: ["load()", "", "", "", "save()"],
  leading_trailing_blanks_dropped: ["", "", "load()", "save()", "", ""],
  mixed_tabs_spaces_shared_prefix_only: ["\t  if ready:", "\t\treturn save()", "\t  return skip()"],
  whitespace_only_line_between: ["  a", "     ", "  b"],
  no_common_prefix: ["a", "  b"],
  non_ascii_body: ["  caf\u00e9()", "  \ud83d\ude00 // emoji", "  \u00a0nbsp_is_not_indent"],
  nbsp_indent_not_stripped: ["\u00a0a", "\u00a0b"],
  trailing_nbsp_kept: ["a\u00a0 \t"],
  carriage_return_inside_line_kept: ["a\r", "b"],
  single_line: ["x"],
  blank_line_then_content: ["", "x"]
};

const spanCanonCases = Object.entries(spanCanonInputs).map(([name, input]) => ({
  name,
  lines: input,
  canonical: canonicalizeSpanLines(input),
  sha256: hashSpanLines(input)
}));

const normalizeNewlinesInputs = {
  mixed: "a\r\nb\rc\nd",
  none: "abc",
  empty: "",
  cr_cr_lf: "\r\r\n",
  lf_cr: "\n\r",
  emoji_crlf: "\ud83d\ude00\r\n\u00e9\r"
};

const normalizeNewlinesCases = Object.entries(normalizeNewlinesInputs).map(([name, input]) => ({
  name,
  input,
  output: normalizeNewlines(input)
}));

// ---------------------------------------------------------------------------
// marker lines and slugs
// ---------------------------------------------------------------------------

const slugInputs = [
  "checkout.apply_coupon",
  "checkout.apply_coupon#tax",
  "checkout.apply_coupon#tax-rate",
  "checkout.apply_coupon#",
  "Checkout.apply",
  "checkout.apply#tax",
  "a",
  "a1_b",
  "_a",
  "1a",
  "a..b",
  "a.",
  ".a",
  "a#b#c",
  "a#b.c-d.e_f",
  "a#-b",
  "a#b.-c",
  "a-b",
  "a b",
  "",
  "caf\u00e9",
  "a#b\n",
  "a\n",
  "a#B"
];

const slugCases = slugInputs.map((slug, index) => ({
  name: `slug_${index}`,
  slug,
  valid: isValidSlug(slug),
  split: splitSlug(slug)
}));

const markerLineInputs = [];
for (const prefix of ["//", "#"]) {
  for (const gap of ["", " "]) {
    const line = (payload) => `${prefix}: @use-case:${gap}${payload}`;
    const tag = `${prefix === "//" ? "slashes" : "hash"}_${gap === "" ? "tight" : "gap"}`;
    const payloads = {
      start: "checkout.apply_coupon#tax",
      begin: "begin checkout.apply_coupon#tax",
      end: "end checkout.apply_coupon#tax",
      ignore_begin: "ignore:begin",
      ignore_end: "ignore:end",
      begin_no_slug: "begin",
      end_no_slug: "end",
      begin_extra: "begin checkout.apply_coupon#tax extra",
      end_extra: "end checkout.apply_coupon#tax extra more",
      start_extra: "checkout.apply_coupon#tax sha256=abc",
      ignore_begin_extra: "ignore:begin foo",
      ignore_end_extra: "ignore:end foo",
      unknown_block: "foo:begin",
      ignore_middle: "ignore:middle",
      invalid_slug: "Checkout.Apply",
      begin_invalid_slug: "begin Bad#",
      end_invalid_slug: "end 1bad",
      empty: ""
    };
    for (const [key, payload] of Object.entries(payloads)) {
      markerLineInputs.push({ name: `${tag}_${key}`, line: line(payload), prefix });
    }
  }
}
markerLineInputs.push(
  { name: "indent_spaces_column", line: "  //: @use-case:end checkout.apply_coupon#tax", prefix: "//" },
  { name: "indent_tabs_column", line: "\t\t//: @use-case:a.b", prefix: "//" },
  { name: "indent_mixed_column", line: " \t //: @use-case:a.b", prefix: "//" },
  { name: "nbsp_indent_is_not_a_marker", line: "\u00a0//: @use-case:a.b", prefix: "//" },
  { name: "ordinary_code", line: "let x = 1", prefix: "//" },
  { name: "ordinary_comment", line: "// a normal comment", prefix: "//" },
  { name: "missing_colon", line: "// @use-case:a.b", prefix: "//" },
  { name: "wrong_prefix", line: "#: @use-case:a.b", prefix: "//" },
  { name: "two_spaces_after_colon", line: "//:  @use-case:a.b", prefix: "//" },
  { name: "trailing_whitespace", line: "//: @use-case:a.b \t ", prefix: "//" },
  { name: "tab_gap", line: "//: @use-case:\ta.b", prefix: "//" },
  { name: "many_gaps_between_tokens", line: "//: @use-case:begin \t  a.b", prefix: "//" },
  { name: "whitespace_only_payload", line: "//: @use-case: \t ", prefix: "//" },
  { name: "nbsp_does_not_separate_tokens", line: "//: @use-case:a.b\u00a0extra", prefix: "//" },
  { name: "non_ascii_slug", line: "//: @use-case:caf\u00e9", prefix: "//" },
  { name: "emoji_payload", line: "//: @use-case:begin \ud83d\ude00", prefix: "//" },
  { name: "combining_mark_after_token", line: "//: @use-case:\u0301a.b", prefix: "//" },
  { name: "combining_mark_on_prefix_colon", line: "//:\u0301 @use-case:a.b", prefix: "//" },
  { name: "colon_inside_slug_token", line: "//: @use-case:a.b:c", prefix: "//" },
  { name: "ignore_begin_uppercase", line: "//: @use-case:IGNORE:BEGIN", prefix: "//" },
  { name: "begin_keyword_uppercase", line: "//: @use-case:BEGIN a.b", prefix: "//" },
  { name: "other_prefix", line: "--: @use-case:a.b", prefix: "--" },
  { name: "empty_line", line: "", prefix: "//" },
  { name: "code_before_marker", line: "x //: @use-case:a.b", prefix: "//" },
  { name: "unknown_block_with_extra", line: "//: @use-case:foo:bar baz", prefix: "//" }
);

const markerLineCases = markerLineInputs.map((entry) => ({
  ...entry,
  parse: parseMarkerLine(entry.line, entry.prefix)
}));

// ---------------------------------------------------------------------------
// comment prefixes
// ---------------------------------------------------------------------------

const extensionInputs = [
  "a.swift",
  "Sources/A.SWIFT",
  ".gitignore",
  "dir/.env",
  "dir.d/file",
  "a\\b.PY",
  "x.",
  "archive.tar.gz",
  "",
  "noext",
  "f.\u0391\u03a3",
  "f.\u0130",
  "f.\u01c5",
  "f.\u03a3x",
  "dir/sub.dir\\name.Rb",
  "/abs/path/.hidden.yml"
];

const extensionCases = extensionInputs.map((path, index) => ({
  name: `extension_${index}`,
  path,
  extension: fileExtension(path)
}));

const prefixInputs = [
  { name: "swift", path: "Sources/Checkout/CouponRules.swift" },
  { name: "typescript", path: "src/scan.ts" },
  { name: "yaml", path: "usecases/checkout.yaml" },
  { name: "python", path: "scripts/run.py" },
  { name: "r_uppercase", path: "analysis.R" },
  { name: "unconfigured", path: "notes.txt" },
  { name: "makefile_no_contents", path: "Makefile" },
  { name: "config_adds", path: "weird.foo", config: { extensions: { ".foo": "//" } } },
  { name: "config_overrides", path: "a.swift", config: { extensions: { ".swift": "#" } } },
  { name: "config_empty_prefix", path: "a.swift", config: { extensions: { ".swift": "" } } },
  { name: "config_key_is_case_sensitive", path: "a.FOO", config: { extensions: { ".FOO": "//" } } },
  { name: "config_without_extensions", path: "a.rb", config: {} },
  {
    name: "config_key_matches_by_exact_code_units_not_canonical_equivalence",
    path: "f.\u00e5",
    config: { extensions: { ".a\u030a": "//" } }
  },
  { name: "shebang_bash", path: "hooks/session-start", contents: "#!/usr/bin/env bash\nset -e\n" },
  { name: "shebang_sh", path: "hooks/run", contents: "#!/bin/sh\necho hi\n" },
  { name: "extensionless_without_shebang", path: "Makefile", contents: "all:\n\techo build\n" },
  { name: "shebang_ignored_with_extension", path: "notes.txt", contents: "#!/bin/sh\n" },
  { name: "shebang_after_whitespace", path: "hooks/run", contents: " #!/bin/sh\n" },
  { name: "dotfile_shebang", path: ".envrc", contents: "#!/bin/sh\n" },
  { name: "empty_contents", path: "hooks/run", contents: "" }
];

const prefixCases = prefixInputs.map((entry) => ({
  name: entry.name,
  path: entry.path,
  config: entry.config ?? null,
  contents: entry.contents ?? null,
  prefix: resolveCommentPrefix(entry.path, entry.config, entry.contents)
}));

// ---------------------------------------------------------------------------
// Swift function recognizer
// ---------------------------------------------------------------------------

function firstMarkerIndex(source) {
  const split = splitPhysicalLines(source);
  const index = split.findIndex((line) => line.text.includes("@use-case:"));
  if (index < 0) {
    throw new Error("no marker line in recognizer fixture");
  }
  return index;
}

const recognizerInputs = {
  // Supported forms.
  main_actor_public_func: lines(
    "import Foundation",
    "",
    "//: @use-case:checkout.apply_coupon",
    "@MainActor",
    "@available(iOS 17, *)",
    "public func applyCoupon(_ code: String) async throws -> Int {",
    "    return 1",
    "}"
  ),
  multiline_generic_where_clause: lines(
    "//: @use-case:checkout.apply_coupon",
    "@MainActor",
    "public func applyCoupon<T>(_ code: String, cart: T) async throws -> CouponResult",
    "    where T: CartLike {",
    "    let coupon = try await repo.find(code)",
    "    return try cart.apply(coupon)",
    "}"
  ),
  bare_func: lines("//: @use-case:a.b", "func f() {", "  doThing()", "}"),
  one_line_func: lines("//: @use-case:a.b", "func f() { doThing() }", "let after = 1"),
  empty_body_same_line: lines("//: @use-case:a.b", "func f() {}"),
  struct_member: lines(
    "struct Cart {",
    "    //: @use-case:cart.total",
    "    func total() -> Int {",
    "        return 0",
    "    }",
    "}"
  ),
  class_func: lines(
    "class C {",
    "    //: @use-case:c.make",
    "    class func make() -> C {",
    "        return C()",
    "    }",
    "}"
  ),
  class_func_split_across_lines: lines(
    "class C {",
    "    //: @use-case:c.make",
    "    class",
    "    func make() -> C {",
    "        return C()",
    "    }",
    "}"
  ),
  static_operator_equals: lines(
    "struct V {",
    "    //: @use-case:v.eq",
    "    static func == (l: V, r: V) -> Bool {",
    "        return true",
    "    }",
    "}"
  ),
  operator_no_space: lines("//: @use-case:v.plus", "static func +(l: V, r: V) -> V {", "  l", "}"),
  prefix_operator: lines("//: @use-case:v.neg", "prefix func -(v: V) -> V {", "  v", "}"),
  generic_operator: lines("//: @use-case:v.op", "func <<< <T>(l: T, r: T) -> T {", "  l", "}"),
  range_operator: lines("//: @use-case:v.range", "static func ..< (l: V, r: V) -> R {", "  R()", "}"),
  extension_where_header: lines(
    "extension Cart",
    "    where Element: Equatable {",
    "    //: @use-case:cart.dedupe",
    "    func dedupe() {",
    "    }",
    "}"
  ),
  enum_member_after_cases: lines(
    "enum E {",
    "    case a, b",
    "    //: @use-case:e.describe",
    "    func describe() -> String {",
    "        switch self {",
    "        case .a: return \"a\"",
    "        case .b: return \"b\"",
    "        }",
    "    }",
    "}"
  ),
  actor_member: lines(
    "actor Store {",
    "    //: @use-case:store.save",
    "    nonisolated func save() {",
    "    }",
    "}"
  ),
  protocol_extension_default: lines(
    "protocol P {}",
    "extension P {",
    "    //: @use-case:p.hello",
    "    func hello() {}",
    "}"
  ),
  nested_type_member: lines(
    "struct Outer {",
    "    struct Inner {",
    "        //: @use-case:outer.inner",
    "        mutating func go() {",
    "        }",
    "    }",
    "}"
  ),
  after_class_var_computed: lines(
    "class K {",
    "    class var shared: K { K() }",
    "    //: @use-case:k.run",
    "    final func run() {",
    "    }",
    "}"
  ),
  multiline_type_header_generic: lines(
    "struct Box<T>",
    "    where T: Hashable,",
    "          T: Sendable {",
    "    //: @use-case:box.put",
    "    func put(_ value: T) {",
    "    }",
    "}"
  ),
  attribute_with_nested_parens: lines(
    "//: @use-case:a.b",
    "@available(iOS, introduced: 17.0, message: \"use (new) api)\")",
    "@objc(doThing:)",
    "func f(_ x: Int) {",
    "}"
  ),
  attribute_on_same_line: lines("//: @use-case:a.b", "@discardableResult public func f() -> Int {", "  1", "}"),
  attributes_and_modifiers_on_separate_lines: lines(
    "//: @use-case:a.b",
    "@MainActor",
    "@Sendable",
    "public",
    "static",
    "func f() {",
    "}"
  ),
  typed_throws_and_some: lines(
    "//: @use-case:a.b",
    "func f() async throws(MyError) -> some View {",
    "  Text(\"x\")",
    "}"
  ),
  rethrows_closure_parameter: lines(
    "//: @use-case:a.b",
    "func f(_ body: () throws -> Void) rethrows {",
    "  try body()",
    "}"
  ),
  default_argument_closure_braces: lines(
    "//: @use-case:a.b",
    "func f(x: () -> Void = { }, y: [Int: Int] = [:]) {",
    "  x()",
    "}"
  ),
  generic_constraints_multiline_signature: lines(
    "//: @use-case:a.b",
    "func f<C: Collection>(",
    "    _ c: C,",
    "    by key: (C.Element) -> Int",
    ") -> [Int]",
    "where C.Element: Equatable",
    "{",
    "    c.map(key)",
    "}"
  ),
  whitespace_before_name_spans_lines: lines("//: @use-case:a.b", "func", "", "   spaced() {", "}"),
  nbsp_before_name: lines("//: @use-case:a.b", "func\u00a0name() {", "}"),
  non_ascii_identifier_truncated: lines("//: @use-case:a.b", "func caf\u00e9() {", "}"),
  closing_brace_followed_by_code: lines("//: @use-case:a.b", "func f() {", "  1", "} // end of f", "func g() {}"),
  nested_control_flow_and_closures: lines(
    "//: @use-case:a.b",
    "func f(items: [Int]) {",
    "    for item in items {",
    "        if item > 0 {",
    "            items.forEach { value in",
    "                print(value)",
    "            }",
    "        } else {",
    "            guard item < 0 else { return }",
    "        }",
    "    }",
    "}",
    "let tail = 0"
  ),
  // Braces hidden in strings and comments.
  braces_in_string_and_comments: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"this } is not a brace\"",
    "    let t = \"neither is this { one\"",
    "    // } a comment brace too",
    "    /* nested /* } */ block */",
    "}"
  ),
  multiline_and_raw_strings: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let m = \"\"\"",
    "    } still in the string {",
    "    \"\"\"",
    "    let r = #\"a raw } brace \"# ",
    "    let n = ##\"raw ## with } brace\"##",
    "}"
  ),
  interpolation_with_closure: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"count=\\(items.map { $0 }.count)\"",
    "    print(s)",
    "}"
  ),
  escaped_quote_before_brace: lines("//: @use-case:a.b", "func f() {", "    let s = \"a\\\"}\"", "}"),
  escaped_backslash_then_quote: lines("//: @use-case:a.b", "func f() {", "    let s = \"\\\\\"", "}"),
  interpolation_nested_parens: lines("//: @use-case:a.b", "func f() {", "    let s = \"\\(g(h(1))) }\"", "}"),
  interpolation_containing_string: lines("//: @use-case:a.b", "func f() {", "    let s = \"\\(\"}\")\"", "}"),
  raw_string_interpolation: lines("//: @use-case:a.b", "func f() {", "    let s = #\"\\#(x) }\"#", "}"),
  raw_string_backslash_not_interpolation: lines("//: @use-case:a.b", "func f() {", "    let s = #\"\\(x) }\"#", "}"),
  raw_string_quote_without_pounds_stays_open: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = #\"a\" } still raw\"#",
    "}"
  ),
  raw_multiline_string: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = #\"\"\"",
    "    } \"\"\" not closed yet {",
    "    \"\"\"#",
    "}"
  ),
  multiline_string_interpolation_spanning: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"\"\"",
    "    \\(items.map {",
    "        $0",
    "    })",
    "    \"\"\"",
    "}"
  ),
  single_line_string_runaway_stops_at_newline: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"unterminated {",
    "}"
  ),
  pound_selector_and_available: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = #selector(go)",
    "    if #available(iOS 17, *) { }",
    "}"
  ),
  brace_between_inner_and_outer_block_comment_close: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    /* outer /* inner */ } still comment */",
    "}"
  ),
  interpolation_parenthesis_then_nested_string: lines(
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"\\(g(1), \"}\")\"",
    "}"
  ),
  line_comment_with_quote: lines("//: @use-case:a.b", "func f() { // \" {", "}"),
  block_comment_with_line_comment_inside: lines("//: @use-case:a.b", "func f() { /* // } */", "}"),
  block_comment_spanning_lines_in_body: lines(
    "//: @use-case:a.b",
    "func f() {",
    "  /*",
    "   }",
    "  */",
    "}"
  ),
  string_with_line_comment_token: lines("//: @use-case:a.b", "func f() {", "  let u = \"http://x/*\"", "}"),
  emoji_and_accents_before_brace: lines(
    "// caf\u00e9 \ud83d\ude00",
    "//: @use-case:a.b",
    "func f() {",
    "    let s = \"\ud83d\ude00}\u00e9\"",
    "    // \u00e9 } \ud83d\ude00",
    "}",
    "// after \ud83d\ude00"
  ),
  crlf_source: crlf("import A", "//: @use-case:a.b", "func f() {", "    let \u00e9 = \"\ud83d\ude00\"", "}", ""),
  crlf_line_comment_brace: crlf("//: @use-case:a.b", "func f() { // }", "}"),
  cr_only_source: "//: @use-case:a.b\rfunc f() {\r  1\r}\r",
  trailing_newline: lines("//: @use-case:a.b", "func f() {", "}", ""),
  trailing_blank_lines_after_body: lines("//: @use-case:a.b", "func f() {", "}", "", ""),
  // Placement rule.
  marker_after_attribute: lines(
    "@MainActor",
    "//: @use-case:checkout.apply_coupon",
    "public func applyCoupon() {",
    "}"
  ),
  marker_after_bare_modifier: lines("public", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_modifier_with_comment: lines("public // why", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_complete_attributed_decl: lines("@objc func a() {}", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_one_line_decl_with_modifier: lines("private var x = 1", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_modifier_with_suffixed_keyword: lines("public funcy", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_modifier_with_underscore_keyword: lines("public foo_func", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_modifier_with_dotted_keyword: lines("public foo.func", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_modifier_with_accented_boundary: lines("public \u00e9func", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_non_modifier_word: lines("publicity", "//: @use-case:a.b", "func f() {", "}"),
  marker_after_indented_attribute: lines("struct S {", "    @inlinable", "    //: @use-case:a.b", "    func f() {", "    }", "}"),
  marker_after_type_header: lines("final class X {", "//: @use-case:a.b", "func f() {", "}", "}"),
  marker_after_blank_whitespace_line: lines("   \t", "//: @use-case:a.b", "func f() {", "}"),
  blank_line_after_marker: lines(
    "//: @use-case:checkout.apply_coupon",
    "",
    "public func applyCoupon() {",
    "}"
  ),
  whitespace_line_after_marker: lines("//: @use-case:a.b", " \t ", "func f() {", "}"),
  comment_after_marker: lines(
    "//: @use-case:checkout.apply_coupon",
    "// TODO: coupon behavior",
    "public func applyCoupon() {",
    "}"
  ),
  block_comment_after_marker: lines("//: @use-case:a.b", "  /* doc */", "func f() {", "}"),
  marker_on_last_line: lines("func f() {", "}", "//: @use-case:a.b"),
  // Unsupported forms.
  protocol_requirement: lines("protocol P {", "    //: @use-case:p.req", "    func required() -> Int", "}"),
  requirement_then_next_func: lines("protocol P {", "    //: @use-case:p.req", "    func a()", "    func b() {}", "}"),
  requirement_then_var: lines("//: @use-case:p.req", "func a() -> Int", "var x: Int { 1 }"),
  requirement_at_end_of_file: lines("//: @use-case:p.req", "func a() -> Int"),
  requirement_then_typealias: lines("//: @use-case:p.req", "func a()", "typealias T = Int"),
  marker_before_var: lines("//: @use-case:a.b", "var x = 1"),
  marker_before_init: lines("//: @use-case:a.b", "init(x: Int) {", "    self.x = x", "}"),
  marker_before_subscript: lines("//: @use-case:a.b", "subscript(i: Int) -> Int {", "    return 0", "}"),
  marker_before_computed_property: lines("//: @use-case:a.b", "var total: Int {", "    return 1", "}"),
  marker_before_class_decl: lines("//: @use-case:a.b", "class Foo {", "}"),
  marker_before_lone_attribute_at_eof: lines("//: @use-case:a.b", "@MainActor"),
  marker_before_open_brace: lines("//: @use-case:a.b", "{", "}"),
  marker_before_unbalanced_attribute_parens: lines("//: @use-case:a.b", "@available(iOS 17", "func f() {", "}"),
  nested_func: lines("func outer() {", "    //: @use-case:a.b", "    func inner() {", "        doThing()", "    }", "}"),
  func_inside_closure: lines("let handler = run {", "    //: @use-case:a.b", "    func helper() {", "    }", "}"),
  func_inside_if_block: lines("if flag {", "    //: @use-case:a.b", "    func helper() {", "    }", "}"),
  func_inside_type_inside_func: lines(
    "func outer() {",
    "    struct Local {",
    "        //: @use-case:a.b",
    "        func helper() {",
    "        }",
    "    }",
    "}"
  ),
  func_inside_closure_argument: lines(
    "run(body: {",
    "    //: @use-case:a.b",
    "    func helper() {",
    "    }",
    "})"
  ),
  type_keyword_in_string_does_not_open_type_scope: lines(
    "let s = \"struct\"; run {",
    "    //: @use-case:a.b",
    "    func helper() {",
    "    }",
    "}"
  ),
  // Conditional compilation.
  declaration_inside_if: lines("#if DEBUG", "//: @use-case:a.b", "func f() {", "}", "#endif"),
  declaration_after_balanced_if: lines("#if DEBUG", "let x = 1", "#endif", "//: @use-case:a.b", "func f() {", "}"),
  indented_if_above: lines("struct S {", "  #if os(macOS)", "  //: @use-case:a.b", "  func f() {", "  }", "  #endif", "}"),
  iffy_is_not_a_directive: lines("#iffy", "//: @use-case:a.b", "func f() {", "}"),
  extra_endif_clamped: lines("#endif", "#if A", "#endif", "//: @use-case:a.b", "func f() {", "}"),
  stray_endif_then_unclosed_if: lines("#endif", "#if A", "//: @use-case:a.b", "func f() {", "}"),
  if_directive_inside_span: lines("//: @use-case:a.b", "func f() {", "#if DEBUG", "    log()", "#endif", "}"),
  elseif_inside_span: lines("//: @use-case:a.b", "func f() {", "    #elseif X", "}"),
  else_inside_span: lines("//: @use-case:a.b", "func f() {", "  #else", "}"),
  elsewhere_is_not_a_directive: lines("//: @use-case:a.b", "func f() {", "  #elsewhere", "}"),
  endif_inside_span: lines("//: @use-case:a.b", "func f() {", "#endif", "}"),
  // Markers inside the span.
  another_marker_inside_span: lines(
    "//: @use-case:checkout.outer",
    "@MainActor",
    "public func outer() {",
    "    //: @use-case:checkout.inner",
    "    doThing()",
    "}"
  ),
  end_marker_inside_span: lines("//: @use-case:a.b", "func f() {", "//: @use-case:end a.b", "}"),
  invalid_marker_inside_span: lines("//: @use-case:a.b", "func f() {", "  //: @use-case:", "}"),
  ignore_marker_inside_span_is_allowed: lines(
    "//: @use-case:a.b",
    "func f() {",
    "  //: @use-case:ignore:begin",
    "  x()",
    "  //: @use-case:ignore:end",
    "}"
  ),
  // Parse errors.
  no_closing_brace: lines("//: @use-case:a.b", "func f() {", "    doThing()"),
  unterminated_multiline_string_swallows_brace: lines("//: @use-case:a.b", "func f() {", "    let s = \"\"\"", "}"),
  unterminated_block_comment_swallows_brace: lines("//: @use-case:a.b", "func f() {", "    /* }"),
  backslash_at_end_of_file: "//: @use-case:a.b\nfunc f() {\n let s = \"abc\\",
  raw_escape_at_end_of_file: "//: @use-case:a.b\nfunc f() {\n let s = #\"abc\\#",
  func_name_missing: lines("//: @use-case:a.b", "func (x: Int) {", "}"),
  func_keyword_at_end_of_file: lines("//: @use-case:a.b", "func"),
  func_keyword_then_brace: lines("//: @use-case:a.b", "func{", "}")
};

const recognizerOutOfRange = [
  { name: "marker_index_negative", source: lines("//: @use-case:a.b", "func f() {}"), index: -1 },
  { name: "marker_index_past_end", source: lines("//: @use-case:a.b", "func f() {}"), index: 2 },
  { name: "marker_index_empty_source", source: "", index: 0 },
  { name: "custom_prefix_marker_inside", source: lines("//: @use-case:a.b", "func f() {", "  #: @use-case:x.y", "}"), index: 0, prefix: "#" },
  { name: "custom_prefix_ignores_slash_marker", source: lines("//: @use-case:a.b", "func f() {", "  //: @use-case:x.y", "}"), index: 0, prefix: "#" }
];

const recognizerEntries = [
  ...Object.entries(recognizerInputs).map(([name, source]) => ({
    name,
    source,
    index: firstMarkerIndex(source),
    prefix: null
  })),
  ...recognizerOutOfRange.map((entry) => ({ ...entry, prefix: entry.prefix ?? null }))
];

const recognizerCases = recognizerEntries.map((entry) => {
  const options = entry.prefix === null ? undefined : { markerCommentPrefix: entry.prefix };
  const result = recognizeSwiftFuncSpan(entry.source, entry.index, options);
  const record = {
    name: entry.name,
    source: entry.source,
    marker_line_index: entry.index,
    marker_comment_prefix: entry.prefix,
    result
  };
  if (result.ok) {
    record.byte_slice = Buffer.from(entry.source, "utf8")
      .subarray(result.span.start_byte, result.span.end_byte)
      .toString("utf8");
    record.span_sha256 = hashSpanLines(result.body_lines);
  }
  return record;
});

// ---------------------------------------------------------------------------
// scanner
// ---------------------------------------------------------------------------

const swiftExplicit = lines(
  "import Foundation",
  "",
  "//: @use-case: checkout.apply_coupon#tax",
  "func computeTax() -> Int {",
  "    return 42",
  "}",
  "//: @use-case: end checkout.apply_coupon#tax"
);

const ignoreBody = (...body) =>
  lines("//: @use-case: begin checkout.apply_coupon", ...body, "//: @use-case: end checkout.apply_coupon");

const scanInputs = [
  { name: "explicit_swift", path: "Sources/Checkout/CouponRules.swift", contents: swiftExplicit },
  {
    name: "explicit_yaml",
    path: "usecases/checkout.yaml",
    contents: lines(
      "name: checkout",
      "",
      "#: @use-case: checkout.apply_coupon#yaml",
      "key: value",
      "list:",
      "  - a",
      "#: @use-case: end checkout.apply_coupon#yaml"
    )
  },
  {
    name: "inferred_swift",
    path: "Sources/Checkout/CouponService.swift",
    contents: lines(
      "import Foundation",
      "",
      "//: @use-case:checkout.apply_coupon#handler",
      "@MainActor",
      "public func applyCoupon(_ code: String) -> Int {",
      "    return 1",
      "}"
    )
  },
  { name: "explicit_end_wins_in_swift", path: "f.swift", contents: lines("//: @use-case:a.b", "func f() {", "    return", "}", "//: @use-case:end a.b") },
  { name: "lone_start_typescript", path: "src/f.ts", contents: lines("//: @use-case:a.b", "export function f() {}") },
  { name: "lone_start_python", path: "scripts/f.py", contents: lines("#: @use-case:a.b", "def f():", "    pass") },
  { name: "unsupported_swift_form", path: "f.swift", contents: lines("//: @use-case:a.b", "var x = 1") },
  { name: "two_inferred_funcs", path: "f.swift", contents: lines("//: @use-case:a.one", "func one() {", "}", "//: @use-case:a.two", "func two() {", "}") },
  { name: "explicit_begin_without_end_in_swift", path: "f.swift", contents: lines("//: @use-case:begin a.b", "func f() {", "}") },
  { name: "adjacent_markers_empty_span", path: "f.swift", contents: lines("x()", "//: @use-case:a.b", "//: @use-case:end a.b", "y()") },
  { name: "adjacent_markers_at_eof_crlf", path: "f.swift", contents: crlf("//: @use-case:a.b", "//: @use-case:end a.b") },
  { name: "ignore_region_excluded", path: "f.swift", contents: ignoreBody("keptBefore()", "//: @use-case:ignore:begin", "ignoredValue(1)", "//: @use-case:ignore:end", "keptAfter()") },
  { name: "ignore_begin_without_end", path: "f.swift", contents: ignoreBody("keptBefore()", "//: @use-case:ignore:begin", "ignoredValue(1)", "keptAfter()") },
  { name: "ignore_end_without_begin", path: "f.swift", contents: ignoreBody("keptBefore()", "//: @use-case:ignore:end", "keptAfter()") },
  { name: "nested_ignore_begin", path: "f.swift", contents: ignoreBody("a()", "//: @use-case:ignore:begin", "b()", "//: @use-case:ignore:begin", "c()", "//: @use-case:ignore:end", "d()") },
  { name: "ignore_markers_outside_spans_are_inert", path: "f.swift", contents: lines("//: @use-case:ignore:end", "//: @use-case:ignore:begin", "x()") },
  { name: "whole_body_ignored", path: "f.swift", contents: ignoreBody("//: @use-case:ignore:begin", "x()", "//: @use-case:ignore:end") },
  { name: "naked_end", path: "f.swift", contents: "//: @use-case: end" },
  { name: "mismatched_end", path: "f.swift", contents: lines("//: @use-case: checkout.apply_coupon", "body()", "//: @use-case: end checkout.other_row") },
  { name: "overlapping_spans", path: "f.ts", contents: lines("//: @use-case:a.one", "//: @use-case:a.two", "//: @use-case:end a.one", "//: @use-case:end a.two") },
  {
    name: "duplicate_start_in_file",
    path: "f.swift",
    contents: lines(
      "//: @use-case: checkout.apply_coupon",
      "a()",
      "//: @use-case: end checkout.apply_coupon",
      "//: @use-case: checkout.apply_coupon",
      "b()",
      "//: @use-case: end checkout.apply_coupon"
    )
  },
  {
    name: "nested_span",
    path: "f.swift",
    contents: lines(
      "//: @use-case: checkout.outer",
      "x()",
      "//: @use-case: checkout.inner",
      "y()",
      "//: @use-case: end checkout.inner",
      "//: @use-case: end checkout.outer"
    )
  },
  {
    name: "nested_span_outer_never_closed_goes_to_inference",
    path: "f.swift",
    contents: lines("//: @use-case:a.outer", "func f() {", "//: @use-case:a.inner", "//: @use-case:end a.inner", "}")
  },
  {
    name: "triple_nesting",
    path: "f.ts",
    contents: lines("//: @use-case:a.one", "//: @use-case:a.two", "//: @use-case:a.three", "//: @use-case:end a.three", "//: @use-case:end a.two", "//: @use-case:end a.one", "//: @use-case:a.four", "x", "//: @use-case:end a.four")
  },
  { name: "forbidden_payloads", path: "f.swift", contents: lines("//: @use-case: checkout.apply_coupon sha256=abc", "//: @use-case: a.b fresh=true", "//: @use-case:", "//: @use-case:foo:bar", "//: @use-case:begin") },
  { name: "end_without_start", path: "f.swift", contents: "//: @use-case: end checkout.apply_coupon" },
  { name: "unconfigured_extension", path: "notes.txt", contents: swiftExplicit },
  { name: "empty_file", path: "f.swift", contents: "" },
  { name: "shebang_script", path: "hooks/session-start", contents: lines("#!/usr/bin/env bash", "#: @use-case:begin hooks.start", "echo hi", "#: @use-case:end hooks.start") },
  { name: "config_prefix_for_swift_disables_inference", path: "f.swift", config: { extensions: { ".swift": "#" } }, contents: lines("#: @use-case:a.b", "func f() {", "}") },
  { name: "config_slashes_for_other_extension", path: "f.foo", config: { extensions: { ".foo": "//" } }, contents: lines("//: @use-case:a.b", "func f() {", "}") },
  { name: "uppercase_swift_extension_infers", path: "F.SWIFT", contents: lines("//: @use-case:a.b", "func f() {", "}") },
  {
    name: "non_ascii_crlf_explicit_offsets",
    path: "Sources/caf\u00e9.swift",
    contents: crlf("// caf\u00e9 \ud83d\ude00", "  //: @use-case:begin a.b#\u00e9x", "//: @use-case:begin a.b#ex", "    let \u00e9 = \"\ud83d\ude00\"   ", "", "", "    \u00e9()\t", "//: @use-case:end a.b#ex", "tail \ud83d\ude00", "")
  },
  {
    name: "non_ascii_inferred_offsets_no_trailing_newline",
    path: "S.swift",
    contents: lines("// \ud83d\ude00\ud83d\ude00", "struct S {", "  //: @use-case:s.go", "  func go() -> String {", "    \"\u00e9\ud83d\ude00}\"", "  }", "}")
  },
  { name: "cr_only_explicit", path: "f.ts", contents: "a\r//: @use-case:a.b\r\u00e9\r//: @use-case:end a.b\r" },
  { name: "indented_markers_columns", path: "f.ts", contents: lines("\t//: @use-case:a.b", "    x()", "  //: @use-case:end a.b") },
  { name: "lone_start_after_mismatch", path: "f.swift", contents: lines("//: @use-case:a.one", "//: @use-case:a.two", "//: @use-case:end a.one", "func f() {", "}") },
  { name: "invalid_marker_inside_explicit_span", path: "f.ts", contents: lines("//: @use-case:a.b", "//: @use-case:A", "//: @use-case:end a.b") },
  { name: "suffixless_and_suffixed", path: "f.ts", contents: lines("//: @use-case:a.b#c.d-e", "x", "//: @use-case:end a.b#c.d-e", "//: @use-case:begin a.b", "y", "//: @use-case:end a.b") }
];

const scanCases = scanInputs.map((entry) => {
  const options = entry.config === undefined ? undefined : { config: entry.config };
  const result = scanFileForMarkers(entry.path, entry.contents, options);
  return {
    name: entry.name,
    path: entry.path,
    contents: entry.contents,
    config: entry.config ?? null,
    result,
    byte_slices: result.bindings.map((binding) =>
      Buffer.from(entry.contents, "utf8").subarray(binding.span.start_byte, binding.span.end_byte).toString("utf8")
    ),
    reports: result.bindings.map((binding) => formatInferredSwiftSpanReport(binding))
  };
});

const scanFilesInputs = [
  {
    name: "cross_file_duplicate",
    inputs: [
      { file_path: "a.swift", contents: swiftExplicit },
      { file_path: "b.swift", contents: swiftExplicit }
    ]
  },
  {
    name: "unconfigured_file_skipped",
    inputs: [{ file_path: "notes.txt", contents: swiftExplicit }]
  },
  {
    name: "in_file_duplicate_is_reported_twice",
    inputs: [
      {
        file_path: "a.ts",
        contents: lines("//: @use-case:a.b", "x", "//: @use-case:end a.b", "//: @use-case:a.b", "y", "//: @use-case:end a.b")
      },
      { file_path: "b.ts", contents: lines("//: @use-case:a.b", "z", "//: @use-case:end a.b") }
    ]
  },
  {
    name: "errors_and_bindings_in_file_order",
    inputs: [
      { file_path: "b.swift", contents: lines("//: @use-case:x.y", "func f() {", "}") },
      { file_path: "a.py", contents: lines("#: @use-case:x.z", "pass") },
      { file_path: "c.yml", contents: lines("#: @use-case:x.y", "k: v", "#: @use-case:end x.y") }
    ]
  },
  { name: "no_files", inputs: [] },
  {
    name: "config_applies_to_every_file",
    config: { extensions: { ".txt": "#" } },
    inputs: [{ file_path: "notes.txt", contents: lines("#: @use-case:a.b", "x", "#: @use-case:end a.b") }]
  }
];

const scanFilesCases = scanFilesInputs.map((entry) => ({
  name: entry.name,
  config: entry.config ?? null,
  inputs: entry.inputs,
  result: scanFiles(entry.inputs, entry.config === undefined ? undefined : { config: entry.config })
}));

// ---------------------------------------------------------------------------
// emit
// ---------------------------------------------------------------------------

const corpus = {
  constants: { ...constants },
  canonical_json: canonicalJsonCases,
  sha256: sha256Cases,
  physical_lines: physicalLineCases,
  span_canon: spanCanonCases,
  normalize_newlines: normalizeNewlinesCases,
  slugs: slugCases,
  marker_lines: markerLineCases,
  file_extensions: extensionCases,
  comment_prefixes: prefixCases,
  recognizer: recognizerCases,
  scan_file: scanCases,
  scan_files: scanFilesCases
};

// Every non-ASCII code unit (including each half of a surrogate pair) becomes
// a \uXXXX escape, so the emitted Swift file is pure ASCII.
const asciiJson = JSON.stringify(corpus).replace(
  /[\u007f-\uffff]/g,
  (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
);

let pounds = "#";
while (asciiJson.includes(`\\${pounds}`) || asciiJson.includes(`"""${pounds}`)) {
  pounds += "#";
}

const names = (cases) => cases.map((entry) => `    ${JSON.stringify(entry.name)},`).join("\n");

const swift = `// swiftlint:disable single_line_closure_body line_length type_body_length
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript marker code. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers returned for the input
// beside it. Span hashes and byte offsets land in ledgers, so these bytes are
// frozen contract (ADR 0007 decision 8).
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-corpus.mjs
enum MarkersGoldenCorpus {
  static let canonicalJSONCaseNames: [String] = [
${names(canonicalJsonCases)}
  ]

  static let physicalLineCaseNames: [String] = [
${names(physicalLineCases)}
  ]

  static let spanCanonicalizerCaseNames: [String] = [
${names(spanCanonCases)}
  ]

  static let markerLineCaseNames: [String] = [
${names(markerLineCases)}
  ]

  static let commentPrefixCaseNames: [String] = [
${names(prefixCases)}
  ]

  static let recognizerCaseNames: [String] = [
${names(recognizerCases)}
  ]

  static let scanFileCaseNames: [String] = [
${names(scanCases)}
  ]

  static let scanFilesCaseNames: [String] = [
${names(scanFilesCases)}
  ]

  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${asciiJson}
  """${pounds}
}

// swiftlint:enable single_line_closure_body line_length type_body_length
`;

writeFileSync(targetPath, swift);
// Read back to prove the escaping round-trips before anyone relies on it.
const written = readFileSync(targetPath, "utf8");
if (!/^[\x00-\x7f]*$/.test(written)) {
  throw new Error("corpus file is not ASCII");
}
console.log(
  `wrote ${targetPath}: ${recognizerCases.length} recognizer, ${scanCases.length} scan-file, ` +
    `${scanFilesCases.length} scan-files, ${markerLineCases.length} marker-line cases`
);
