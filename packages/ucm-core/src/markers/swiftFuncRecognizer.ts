// Swift function recognizer for inferred-end markers (spec section 9).
//
// This is the only inferred-end recognizer in v1. There is no Swift toolchain in
// this Node repo, so this is a careful hand-written Swift *declaration* recognizer
// in TypeScript. It MUST fail closed: if it cannot prove the exact span with
// confidence, it returns an INVALID result with one of the section 9.4 codes --
// it never guesses.
//
// The recognizer:
//   * lexes the source into a "code mask" that correctly skips line comments,
//     nestable block comments, normal/multiline/raw string literals (incl.
//     `#"..."#`), character escapes, and string interpolation `\(...)`, so that
//     brace-matching runs ONLY over real code braces;
//   * enforces the strict placement rule (9.2): the marker must be immediately
//     adjacent to the declaration group -- no blank line, no comment, and it may
//     not sit after an attached attribute/modifier;
//   * computes the span extent (9.3): from the first attached attribute/modifier
//     line, through the full signature (generics + where-clause, multiline ok),
//     to the line of the function body's closing brace;
//   * rejects every unsupported / ambiguous form (9.1, 9.4) closed.
import { splitPhysicalLines, lineIndexOfChar } from "./physicalLines.js";
import { parseMarkerLine } from "./markerLine.js";

// Section 9.4 ambiguity / unsupported-form failure codes. Every one is an
// INVALID for inferred mode; the caller must require an explicit end instead.
export const SwiftFuncErrorCode = Object.freeze({
  NO_SWIFT_PARSER: "NO_SWIFT_PARSER",
  SWIFT_PARSE_ERROR_IN_REGION: "SWIFT_PARSE_ERROR_IN_REGION",
  MARKER_NOT_ADJACENT_TO_DECLARATION: "MARKER_NOT_ADJACENT_TO_DECLARATION",
  MARKER_INSIDE_ATTACHED_DECLARATION: "MARKER_INSIDE_ATTACHED_DECLARATION",
  NEXT_NODE_NOT_FUNC: "NEXT_NODE_NOT_FUNC",
  FUNC_HAS_NO_BODY: "FUNC_HAS_NO_BODY",
  FUNC_BODY_HAS_NO_CLOSING_BRACE: "FUNC_BODY_HAS_NO_CLOSING_BRACE",
  NESTED_FUNC_UNSUPPORTED: "NESTED_FUNC_UNSUPPORTED",
  CONDITIONAL_COMPILATION_IN_SPAN: "CONDITIONAL_COMPILATION_IN_SPAN",
  ANOTHER_MARKER_INSIDE_SPAN: "ANOTHER_MARKER_INSIDE_SPAN",
  MULTIPLE_CANDIDATE_DECLARATIONS: "MULTIPLE_CANDIDATE_DECLARATIONS"
} as const);

export type SwiftFuncErrorCode = (typeof SwiftFuncErrorCode)[keyof typeof SwiftFuncErrorCode];

export interface SwiftFuncSpan {
  start_line: number; // 1-based, first attached attribute/modifier/func line
  end_line: number; // 1-based, line of the body's closing brace
  start_byte: number; // UTF-8 byte offset of the first byte of start_line
  end_byte: number; // UTF-8 byte offset just past end_line's terminator (or EOF)
}

export type SwiftFuncRecognizerResult =
  | { ok: true; span: SwiftFuncSpan; symbol_name: string; body_lines: string[] }
  | { ok: false; code: SwiftFuncErrorCode; message: string; line: number };

export interface SwiftFuncRecognizerOptions {
  // The marker comment prefix used to detect markers inside the computed span
  // (spec 9.3 rule 9). Defaults to Swift's "//".
  markerCommentPrefix?: string;
}

// ---------------------------------------------------------------------------
// Code mask: 1 = the char is real code, 0 = inside a string/comment delimiter
// or body. Interpolated code `\(...)` inside a string is marked as code (1).
// ---------------------------------------------------------------------------

type LexCtx =
  | { t: "code" }
  | { t: "interp"; parenDepth: number }
  | { t: "line_comment" }
  | { t: "block_comment"; depth: number }
  | { t: "string"; multiline: boolean; pounds: number };

interface CodeMaskResult {
  mask: Uint8Array; // 1 where char index is code context
  terminated: boolean; // false if a string/comment was left open at EOF
}

function poundsRun(src: string, from: number): number {
  let j = from;
  while (j < src.length && src[j] === "#") {
    j += 1;
  }
  return j - from;
}

// Build the code mask for the whole source with a stack-based lexer.
function computeCodeMask(src: string): CodeMaskResult {
  const n = src.length;
  const mask = new Uint8Array(n);
  const stack: LexCtx[] = [{ t: "code" }];
  let i = 0;

  const top = (): LexCtx => stack[stack.length - 1];

  while (i < n) {
    const ctx = top();
    const c = src[i];

    if (ctx.t === "code" || ctx.t === "interp") {
      mask[i] = 1;
      // Comments.
      if (c === "/" && src[i + 1] === "/") {
        stack.push({ t: "line_comment" });
        i += 2;
        continue;
      }
      if (c === "/" && src[i + 1] === "*") {
        stack.push({ t: "block_comment", depth: 1 });
        i += 2;
        continue;
      }
      // Raw string `#..#"..."#..#` (also raw multiline `#"""..."""#`).
      if (c === "#") {
        const pounds = poundsRun(src, i);
        const q = i + pounds;
        if (src[q] === '"') {
          const multiline = src[q + 1] === '"' && src[q + 2] === '"';
          stack.push({ t: "string", multiline, pounds });
          i = q + (multiline ? 3 : 1);
          continue;
        }
        // `#` not opening a raw string (e.g. `#if`, `#selector`): ordinary char.
        i += 1;
        continue;
      }
      // Normal / multiline string.
      if (c === '"') {
        const multiline = src[i + 1] === '"' && src[i + 2] === '"';
        stack.push({ t: "string", multiline, pounds: 0 });
        i += multiline ? 3 : 1;
        continue;
      }
      // Interpolation paren tracking (return to the owning string on close).
      if (ctx.t === "interp") {
        if (c === "(") {
          ctx.parenDepth += 1;
          i += 1;
          continue;
        }
        if (c === ")") {
          if (ctx.parenDepth === 0) {
            stack.pop();
            i += 1;
            continue;
          }
          ctx.parenDepth -= 1;
          i += 1;
          continue;
        }
      }
      i += 1;
      continue;
    }

    if (ctx.t === "line_comment") {
      if (c === "\n") {
        stack.pop();
      }
      i += 1;
      continue;
    }

    if (ctx.t === "block_comment") {
      if (c === "/" && src[i + 1] === "*") {
        ctx.depth += 1;
        i += 2;
        continue;
      }
      if (c === "*" && src[i + 1] === "/") {
        ctx.depth -= 1;
        i += 2;
        if (ctx.depth === 0) {
          stack.pop();
        }
        continue;
      }
      i += 1;
      continue;
    }

    // ctx.t === "string"
    const { multiline, pounds } = ctx;
    if (pounds === 0) {
      if (c === "\\") {
        if (src[i + 1] === "(") {
          stack.push({ t: "interp", parenDepth: 0 });
          i += 2;
          continue;
        }
        i += 2; // escaped char
        continue;
      }
      if (!multiline) {
        if (c === '"') {
          stack.pop();
          i += 1;
          continue;
        }
        if (c === "\n") {
          // Single-line string cannot span lines; stop runaway, fail closed.
          stack.pop();
          i += 1;
          continue;
        }
        i += 1;
        continue;
      }
      // multiline
      if (c === '"' && src[i + 1] === '"' && src[i + 2] === '"') {
        stack.pop();
        i += 3;
        continue;
      }
      i += 1;
      continue;
    }

    // raw string (pounds > 0): escapes are `\` + pounds `#`.
    const hashes = "#".repeat(pounds);
    if (c === "\\" && src.startsWith(hashes, i + 1)) {
      if (src[i + 1 + pounds] === "(") {
        stack.push({ t: "interp", parenDepth: 0 });
        i += 2 + pounds;
        continue;
      }
      i += 2 + pounds;
      continue;
    }
    if (!multiline) {
      if (c === '"' && src.startsWith(hashes, i + 1)) {
        stack.pop();
        i += 1 + pounds;
        continue;
      }
      i += 1;
      continue;
    }
    // raw multiline
    if (
      c === '"' &&
      src[i + 1] === '"' &&
      src[i + 2] === '"' &&
      src.startsWith(hashes, i + 3)
    ) {
      stack.pop();
      i += 3 + pounds;
      continue;
    }
    i += 1;
    continue;
  }

  const terminated = stack.length === 1 && stack[0].t === "code";
  return { mask, terminated };
}

// ---------------------------------------------------------------------------
// Code tokenization over the masked source (words + structural punctuation).
// ---------------------------------------------------------------------------

type TokKind = "word" | "lbrace" | "rbrace" | "lparen" | "rparen" | "lbracket" | "rbracket" | "at" | "newline";

interface Tok {
  kind: TokKind;
  text: string; // for "word"
  pos: number; // char index of first char
}

const WORD_START = /[A-Za-z_]/;
const WORD_CHAR = /[A-Za-z0-9_]/;

// Tokenize the code-context characters in [from, to). Strings/comments are
// skipped (mask == 0). Newlines are emitted as tokens so callers can detect
// statement boundaries.
function tokenizeCode(src: string, mask: Uint8Array, from: number, to: number): Tok[] {
  const toks: Tok[] = [];
  let i = from;
  const end = Math.min(to, src.length);
  while (i < end) {
    const c = src[i];
    if (c === "\n") {
      toks.push({ kind: "newline", text: "\n", pos: i });
      i += 1;
      continue;
    }
    if (mask[i] === 0) {
      i += 1;
      continue;
    }
    if (WORD_START.test(c)) {
      let j = i + 1;
      while (j < end && WORD_CHAR.test(src[j])) {
        j += 1;
      }
      toks.push({ kind: "word", text: src.slice(i, j), pos: i });
      i = j;
      continue;
    }
    switch (c) {
      case "{":
        toks.push({ kind: "lbrace", text: c, pos: i });
        break;
      case "}":
        toks.push({ kind: "rbrace", text: c, pos: i });
        break;
      case "(":
        toks.push({ kind: "lparen", text: c, pos: i });
        break;
      case ")":
        toks.push({ kind: "rparen", text: c, pos: i });
        break;
      case "[":
        toks.push({ kind: "lbracket", text: c, pos: i });
        break;
      case "]":
        toks.push({ kind: "rbracket", text: c, pos: i });
        break;
      case "@":
        toks.push({ kind: "at", text: c, pos: i });
        break;
      default:
        break;
    }
    i += 1;
  }
  return toks;
}

// Access / behavior modifiers that may precede the declaration keyword. The
// recognizer skips these when classifying the next declaration.
const MODIFIERS = new Set([
  "public",
  "private",
  "internal",
  "fileprivate",
  "open",
  "static",
  "final",
  "override",
  "required",
  "convenience",
  "lazy",
  "weak",
  "unowned",
  "mutating",
  "nonmutating",
  "dynamic",
  "optional",
  "indirect",
  "prefix",
  "postfix",
  "infix",
  "nonisolated",
  "distributed",
  "unsafe",
  "borrowing",
  "consuming",
  "package"
]);

// Declaration keywords that open a *type* body (allowed enclosing scope for an
// inferred member func).
const TYPE_DECL = new Set(["extension", "struct", "class", "enum", "protocol", "actor"]);

// ---------------------------------------------------------------------------
// Scope analysis: classify every enclosing brace as a type body vs anything
// else (func body, closure, control-flow block, accessor, ...). An inferred
// func is only supported when every enclosing scope is a type body.
// ---------------------------------------------------------------------------

function enclosingScopesAllTypes(src: string, mask: Uint8Array, untilChar: number): boolean {
  const toks = tokenizeCode(src, mask, 0, untilChar);
  const scope: ("type" | "other")[] = [];
  let parenDepth = 0;
  let stmtLead: string | null = null;

  for (const t of toks) {
    switch (t.kind) {
      case "lparen":
      case "lbracket":
        parenDepth += 1;
        break;
      case "rparen":
      case "rbracket":
        if (parenDepth > 0) {
          parenDepth -= 1;
        }
        break;
      case "newline":
        // Statement boundary at paren depth 0. Keep an in-flight *type* lead
        // alive across newlines so multiline type headers (e.g. an extension
        // with a where-clause) still classify their body as a type scope.
        if (parenDepth === 0 && !(stmtLead !== null && TYPE_DECL.has(stmtLead))) {
          stmtLead = null;
        }
        break;
      case "lbrace": {
        const kind = stmtLead !== null && TYPE_DECL.has(stmtLead) ? "type" : "other";
        scope.push(kind);
        stmtLead = null;
        break;
      }
      case "rbrace":
        if (scope.length > 0) {
          scope.pop();
        }
        stmtLead = null;
        break;
      case "word": {
        if (MODIFIERS.has(t.text)) {
          break; // modifiers do not establish the declaration kind
        }
        if (stmtLead === null) {
          stmtLead = t.text;
        } else if (stmtLead === "class" && (t.text === "func" || t.text === "var" || t.text === "subscript" || t.text === "init")) {
          // `class func` / `class var`: the leading `class` is a modifier here.
          stmtLead = t.text;
        }
        break;
      }
      default:
        break;
    }
  }

  return scope.every((s) => s === "type");
}

// ---------------------------------------------------------------------------
// Helpers for line classification.
// ---------------------------------------------------------------------------

function isBlank(text: string): boolean {
  return /^[ \t]*$/.test(text);
}

function trimmed(text: string): string {
  return text.replace(/^[ \t]+/, "");
}

// A line that begins (after indentation) an attached attribute or a bare
// modifier -- i.e. part of a declaration group. Used to detect a marker placed
// *inside* the attached declaration (spec 9.2: marker after `@MainActor`).
function startsAttachedDecl(text: string): boolean {
  const t = trimmed(text);
  if (t.startsWith("@")) {
    return true;
  }
  const firstWord = /^([A-Za-z_][A-Za-z0-9_]*)/.exec(t);
  if (firstWord && MODIFIERS.has(firstWord[1])) {
    // Only treat it as an attached modifier line if it does NOT itself contain
    // the declaration keyword (a one-line decl above is a separate statement).
    return !/\b(func|var|let|init|deinit|subscript|class|struct|enum|protocol|actor|extension|typealias|case)\b/.test(
      t
    );
  }
  return false;
}

const CONDITIONAL_DIRECTIVE = /^#(if|elseif|else|endif)\b/;

// ---------------------------------------------------------------------------
// Recognizer.
// ---------------------------------------------------------------------------

function fail(code: SwiftFuncErrorCode, message: string, line: number): SwiftFuncRecognizerResult {
  return { ok: false, code, message, line };
}

// Recognize the inferred Swift function span for a marker at `markerLineIndex`
// (0-based). Returns the proven span or an INVALID result with a 9.4 code.
export function recognizeSwiftFuncSpan(
  source: string,
  markerLineIndex: number,
  options?: SwiftFuncRecognizerOptions
): SwiftFuncRecognizerResult {
  const markerPrefix = options?.markerCommentPrefix ?? "//";
  const lines = splitPhysicalLines(source);
  const markerLineNo = markerLineIndex + 1; // 1-based, for diagnostics

  if (markerLineIndex < 0 || markerLineIndex >= lines.length) {
    return fail(
      SwiftFuncErrorCode.MARKER_NOT_ADJACENT_TO_DECLARATION,
      "marker line is out of range",
      markerLineNo
    );
  }

  // --- Placement rule (spec 9.2). ------------------------------------------
  // The marker may not sit after an attached attribute/modifier: if the line
  // immediately above is an attribute or bare modifier, the marker is inside
  // the declaration group.
  if (markerLineIndex > 0) {
    const above = lines[markerLineIndex - 1].text;
    if (!isBlank(above) && startsAttachedDecl(above)) {
      return fail(
        SwiftFuncErrorCode.MARKER_INSIDE_ATTACHED_DECLARATION,
        "marker is placed after an attached attribute/modifier; move it before the whole declaration group",
        markerLineNo
      );
    }
  }

  // The declaration group must begin on the very next line: no blank line and
  // no comment between the marker and the first attribute/modifier/func token.
  const belowIdx = markerLineIndex + 1;
  if (belowIdx >= lines.length) {
    return fail(
      SwiftFuncErrorCode.MARKER_NOT_ADJACENT_TO_DECLARATION,
      "marker has no declaration after it",
      markerLineNo
    );
  }
  const belowText = lines[belowIdx].text;
  if (isBlank(belowText)) {
    return fail(
      SwiftFuncErrorCode.MARKER_NOT_ADJACENT_TO_DECLARATION,
      "blank line between marker and declaration",
      markerLineNo
    );
  }
  const belowTrim = trimmed(belowText);
  if (belowTrim.startsWith("//") || belowTrim.startsWith("/*")) {
    return fail(
      SwiftFuncErrorCode.MARKER_NOT_ADJACENT_TO_DECLARATION,
      "comment between marker and declaration",
      markerLineNo
    );
  }

  // --- Conditional compilation enclosing the declaration (spec 9.3 rule 8). --
  // If an unbalanced `#if` is open at the declaration start, the declaration is
  // inside conditional compilation -> fail closed.
  let condDepth = 0;
  for (let i = 0; i < belowIdx; i += 1) {
    const t = trimmed(lines[i].text);
    if (/^#if\b/.test(t)) {
      condDepth += 1;
    } else if (/^#endif\b/.test(t)) {
      condDepth = Math.max(0, condDepth - 1);
    }
  }
  if (condDepth > 0) {
    return fail(
      SwiftFuncErrorCode.CONDITIONAL_COMPILATION_IN_SPAN,
      "declaration is inside a #if conditional-compilation block",
      markerLineNo
    );
  }

  // --- Lex the whole file once. --------------------------------------------
  const { mask } = computeCodeMask(source);

  // --- Classify the next declaration and locate its body. ------------------
  const declStartChar = lines[belowIdx].charStart;
  const toks = tokenizeCode(source, mask, declStartChar, source.length);

  // Skip attached attributes (`@Name(...)`) and modifiers; the next bare
  // declaration keyword classifies the node.
  let k = 0;
  // Skip attributes: `@` word optional balanced `(...)`.
  for (;;) {
    if (k < toks.length && toks[k].kind === "at") {
      k += 1; // '@'
      if (k < toks.length && toks[k].kind === "word") {
        k += 1; // attribute name
      }
      // optional balanced (...) argument list
      if (k < toks.length && toks[k].kind === "lparen") {
        let depth = 0;
        while (k < toks.length) {
          if (toks[k].kind === "lparen") {
            depth += 1;
          } else if (toks[k].kind === "rparen") {
            depth -= 1;
            if (depth === 0) {
              k += 1;
              break;
            }
          }
          k += 1;
        }
      }
      continue;
    }
    if (k < toks.length && toks[k].kind === "newline") {
      k += 1;
      continue;
    }
    break;
  }
  // Skip modifiers (and blank-line newlines between them).
  while (k < toks.length) {
    const t = toks[k];
    if (t.kind === "newline") {
      k += 1;
      continue;
    }
    if (t.kind === "word" && MODIFIERS.has(t.text)) {
      k += 1;
      continue;
    }
    if (t.kind === "word" && t.text === "class") {
      // `class func`: a leading `class` here is a type-method modifier, not a
      // type declaration. Only skip it when a `func` keyword follows.
      let j = k + 1;
      while (j < toks.length && toks[j].kind === "newline") {
        j += 1;
      }
      if (j < toks.length && toks[j].kind === "word" && toks[j].text === "func") {
        k += 1;
        continue;
      }
    }
    break;
  }

  // The classifying token.
  const head = toks[k];
  if (!head || head.kind !== "word" || head.text !== "func") {
    return fail(
      SwiftFuncErrorCode.NEXT_NODE_NOT_FUNC,
      `the declaration after the marker is not a func (${head ? head.text ?? head.kind : "end of file"})`,
      markerLineNo
    );
  }

  // Symbol name: read the source right after the `func` keyword. It is either
  // an identifier (`applyCoupon`, possibly followed by a generic `<...>`) or an
  // operator run (`==`, `<`, `+`, ...).
  let s = head.pos + "func".length;
  while (s < source.length && /\s/.test(source[s])) {
    s += 1;
  }
  const idMatch = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(s));
  let symbolName: string;
  if (idMatch) {
    symbolName = idMatch[0];
  } else {
    // Operator function name: a run of operator chars (stop at `(`, `{`, `[`).
    const opMatch = /^[^\sA-Za-z0-9_({[]+/.exec(source.slice(s));
    symbolName = opMatch ? opMatch[0] : "";
  }
  if (symbolName === "") {
    return fail(
      SwiftFuncErrorCode.SWIFT_PARSE_ERROR_IN_REGION,
      "could not read the function name",
      markerLineNo
    );
  }

  // --- Nesting check (spec 9.1 / 9.3 rule 7). ------------------------------
  if (!enclosingScopesAllTypes(source, mask, head.pos)) {
    return fail(
      SwiftFuncErrorCode.NESTED_FUNC_UNSUPPORTED,
      "func is nested inside a function/closure/non-type scope; inferred mode supports only top-level and type-member funcs",
      markerLineNo
    );
  }

  // --- Find the body open brace (first `{` at paren/bracket depth 0). -------
  // Stop if we hit a closing `}` (enclosing scope) or a new declaration keyword
  // first -> the func has no body (protocol requirement, abstract decl).
  let bodyOpenTokIdx = -1;
  {
    let parenDepth = 0;
    for (let p = k + 1; p < toks.length; p += 1) {
      const t = toks[p];
      if (t.kind === "lparen" || t.kind === "lbracket") {
        parenDepth += 1;
      } else if (t.kind === "rparen" || t.kind === "rbracket") {
        if (parenDepth > 0) {
          parenDepth -= 1;
        }
      } else if (t.kind === "lbrace") {
        if (parenDepth === 0) {
          bodyOpenTokIdx = p;
          break;
        }
      } else if (t.kind === "rbrace") {
        if (parenDepth === 0) {
          return fail(
            SwiftFuncErrorCode.FUNC_HAS_NO_BODY,
            "func has no body (no opening brace before the enclosing scope closes)",
            markerLineNo
          );
        }
      } else if (
        t.kind === "word" &&
        parenDepth === 0 &&
        (t.text === "func" ||
          t.text === "var" ||
          t.text === "let" ||
          t.text === "struct" ||
          t.text === "class" ||
          t.text === "enum" ||
          t.text === "protocol" ||
          t.text === "extension" ||
          t.text === "init" ||
          t.text === "deinit" ||
          t.text === "subscript" ||
          t.text === "typealias")
      ) {
        return fail(
          SwiftFuncErrorCode.FUNC_HAS_NO_BODY,
          "func has no body (next declaration starts before a body brace)",
          markerLineNo
        );
      }
    }
  }
  if (bodyOpenTokIdx < 0) {
    return fail(
      SwiftFuncErrorCode.FUNC_HAS_NO_BODY,
      "func has no body",
      markerLineNo
    );
  }

  // --- Brace-match the body to its closing brace (code-context braces only). -
  const openPos = toks[bodyOpenTokIdx].pos;
  let depth = 0;
  let closePos = -1;
  for (let p = openPos; p < source.length; p += 1) {
    if (mask[p] === 0) {
      continue;
    }
    const ch = source[p];
    if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        closePos = p;
        break;
      }
    }
  }
  if (closePos < 0) {
    return fail(
      SwiftFuncErrorCode.FUNC_BODY_HAS_NO_CLOSING_BRACE,
      "func body has no closing brace",
      markerLineNo
    );
  }

  // --- Span extent (spec 9.3). ---------------------------------------------
  const startLineIdx = belowIdx; // first attribute/modifier/func line
  const endLineIdx = lineIndexOfChar(lines, closePos);
  if (endLineIdx < 0) {
    return fail(
      SwiftFuncErrorCode.SWIFT_PARSE_ERROR_IN_REGION,
      "could not locate the closing-brace line",
      markerLineNo
    );
  }

  // --- No marker may appear inside the computed span (spec 9.3 rule 9). -----
  for (let i = startLineIdx; i <= endLineIdx; i += 1) {
    const parse = parseMarkerLine(lines[i].text, markerPrefix);
    if (parse.kind === "start" || parse.kind === "end" || parse.kind === "invalid") {
      return fail(
        SwiftFuncErrorCode.ANOTHER_MARKER_INSIDE_SPAN,
        `another use-case marker appears inside the computed span (line ${i + 1})`,
        markerLineNo
      );
    }
  }

  // --- No conditional-compilation directive inside the span (9.3 rule 8). ---
  for (let i = startLineIdx; i <= endLineIdx; i += 1) {
    if (CONDITIONAL_DIRECTIVE.test(trimmed(lines[i].text))) {
      return fail(
        SwiftFuncErrorCode.CONDITIONAL_COMPILATION_IN_SPAN,
        `conditional-compilation directive inside the computed span (line ${i + 1})`,
        markerLineNo
      );
    }
  }

  const startLine = lines[startLineIdx];
  const endLine = lines[endLineIdx];
  const bodyLines = lines.slice(startLineIdx, endLineIdx + 1).map((l) => l.text);

  return {
    ok: true,
    span: {
      start_line: startLineIdx + 1,
      end_line: endLineIdx + 1,
      start_byte: startLine.byteStart,
      end_byte: endLine.byteEnd
    },
    symbol_name: symbolName,
    body_lines: bodyLines
  };
}
