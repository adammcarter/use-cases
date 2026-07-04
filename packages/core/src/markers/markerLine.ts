// Marker-line parser (spec section 1: grammar 1.2, slug rules 1.3).
//
// Recognizes one physical source line of the form
//   <comment-prefix>: @use-case:<payload>
// and classifies it as a start marker, an end marker, "not a marker", or an
// INVALID marker with a precise error code. The marker carries identity ONLY:
// any payload beyond a bare slug, a valid `begin <slug>`, or a valid
// `end <slug>` is rejected as a forbidden payload.

// Stable error codes for every way a marker / span can be invalid. Marker-line
// codes are produced here; span-pairing codes are produced by the scanner.
export const MarkerErrorCode = Object.freeze({
  // Marker-line level.
  FORBIDDEN_MARKER_PAYLOAD: "FORBIDDEN_MARKER_PAYLOAD",
  MALFORMED_MARKER: "MALFORMED_MARKER",
  MALFORMED_END_MARKER: "MALFORMED_END_MARKER",
  // Span-pairing level.
  MISMATCHED_END_MARKER: "MISMATCHED_END_MARKER",
  END_WITHOUT_START: "END_WITHOUT_START",
  UNSUPPORTED_INFERENCE: "UNSUPPORTED_INFERENCE",
  NESTED_SPAN: "NESTED_SPAN",
  DUPLICATE_BINDING_SLUG: "DUPLICATE_BINDING_SLUG"
} as const);

export type MarkerErrorCode = (typeof MarkerErrorCode)[keyof typeof MarkerErrorCode];

// Full slug grammar (spec 1.2 / 1.3):
//   slug           = row-id ["#" binding-suffix]
//   row-id         = ident {"." ident}
//   binding-suffix = suffix-ident {"." suffix-ident}
//   ident          = lower-alpha {lower-alpha | digit | "_"}
//   suffix-ident   = lower-alpha {lower-alpha | digit | "_" | "-"}
const ROW_ID = "[a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*)*";
const BINDING_SUFFIX = "[a-z][a-z0-9_-]*(?:\\.[a-z][a-z0-9_-]*)*";
const SLUG_RE = new RegExp(`^${ROW_ID}(?:#${BINDING_SUFFIX})?$`);

export function isValidSlug(slug: string): boolean {
  return SLUG_RE.test(slug);
}

// Split a valid slug into its row id and optional binding suffix.
// Returns null when the slug is not grammatical.
export function splitSlug(slug: string): { row_id: string; suffix: string | null } | null {
  if (!isValidSlug(slug)) {
    return null;
  }
  const hash = slug.indexOf("#");
  if (hash < 0) {
    return { row_id: slug, suffix: null };
  }
  return { row_id: slug.slice(0, hash), suffix: slug.slice(hash + 1) };
}

export type MarkerLineParse =
  | { kind: "none" }
  | { kind: "start"; slug: string; explicit: boolean; column: number }
  | { kind: "end"; slug: string; column: number }
  | { kind: "invalid"; code: MarkerErrorCode; message: string; column: number; slug?: string };

// Parse a single physical line against a known comment prefix.
//
// A line is only considered a marker if, after optional leading whitespace, it
// begins with exactly `<prefix>: @use-case:`. Otherwise it is "none" (an
// ordinary line/comment that the scanner ignores). Once that token matches, the
// payload MUST be a bare slug, `begin <slug>`, or `end <slug>`; anything else is
// invalid. A single space after the marker token is tolerated for compatibility.
export function parseMarkerLine(line: string, commentPrefix: string): MarkerLineParse {
  const indentMatch = /^[ \t]*/.exec(line);
  const indent = indentMatch ? indentMatch[0] : "";
  const column = indent.length + 1;
  const rest = line.slice(indent.length);

  const token = `${commentPrefix}: @use-case:`;
  if (!rest.startsWith(token)) {
    return { kind: "none" };
  }

  const payloadRaw = rest.slice(token.length);
  const payload = payloadRaw.replace(/^[ \t]+/, "").replace(/[ \t]+$/, "");
  if (payload === "") {
    return {
      kind: "invalid",
      code: MarkerErrorCode.MALFORMED_MARKER,
      message: "use-case marker has an empty payload",
      column
    };
  }

  const tokens = payload.split(/[ \t]+/);

  if (tokens[0] === "begin") {
    if (tokens.length === 1) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.MALFORMED_MARKER,
        message: "begin marker has no slug; expected `begin <slug>`",
        column
      };
    }
    if (tokens.length > 2) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.FORBIDDEN_MARKER_PAYLOAD,
        message: `forbidden payload after begin slug: ${tokens.slice(2).join(" ")}`,
        column,
        slug: tokens[1]
      };
    }
    const slug = tokens[1];
    if (!isValidSlug(slug)) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.MALFORMED_MARKER,
        message: `invalid slug in begin marker: ${slug}`,
        column,
        slug
      };
    }
    return { kind: "start", slug, explicit: true, column };
  }

  if (tokens[0] === "end") {
    if (tokens.length === 1) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.MALFORMED_END_MARKER,
        message: "end marker has no slug; expected `end <slug>`",
        column
      };
    }
    if (tokens.length > 2) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.FORBIDDEN_MARKER_PAYLOAD,
        message: `forbidden payload after end slug: ${tokens.slice(2).join(" ")}`,
        column,
        slug: tokens[1]
      };
    }
    const slug = tokens[1];
    if (!isValidSlug(slug)) {
      return {
        kind: "invalid",
        code: MarkerErrorCode.MALFORMED_MARKER,
        message: `invalid slug in end marker: ${slug}`,
        column,
        slug
      };
    }
    return { kind: "end", slug, column };
  }

  // Start marker: payload must be exactly one valid slug.
  if (tokens.length > 1) {
    return {
      kind: "invalid",
      code: MarkerErrorCode.FORBIDDEN_MARKER_PAYLOAD,
      message: `forbidden payload after slug: ${tokens.slice(1).join(" ")}`,
      column,
      slug: tokens[0]
    };
  }
  const slug = tokens[0];
  if (!isValidSlug(slug)) {
    return {
      kind: "invalid",
      code: MarkerErrorCode.MALFORMED_MARKER,
      message: `invalid slug: ${slug}`,
      column,
      slug
    };
  }
  return { kind: "start", slug, explicit: false, column };
}
