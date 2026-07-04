// Comment-prefix resolver (spec section 1.1, Amendment 1).
//
// The semantic marker is `<line-comment-prefix>: @use-case:<payload>`. The
// line-comment prefix is not universal (`//` is invalid in Python/YAML/shell),
// so it is resolved per file extension from a config-driven map. A default map
// covers the common `//` and `#` languages so explicit spans work out of the box.

export interface CommentPrefixConfig {
  // Extension (with leading dot, lower-cased, e.g. ".swift") -> line-comment prefix.
  // Merged over DEFAULT_COMMENT_PREFIXES; an entry here overrides the default.
  extensions?: Record<string, string>;
}

// Default extension -> line-comment prefix map.
// Identity-only: this decides *how a marker comment is written*, nothing more.
export const DEFAULT_COMMENT_PREFIXES: Readonly<Record<string, string>> = Object.freeze({
  // `//` languages.
  ".swift": "//",
  ".ts": "//",
  ".tsx": "//",
  ".js": "//",
  ".jsx": "//",
  ".mjs": "//",
  ".cjs": "//",
  ".c": "//",
  ".cc": "//",
  ".cpp": "//",
  ".cxx": "//",
  ".h": "//",
  ".hpp": "//",
  ".m": "//",
  ".mm": "//",
  ".java": "//",
  ".kt": "//",
  ".kts": "//",
  ".go": "//",
  ".rs": "//",
  ".scala": "//",
  // `#` languages.
  ".py": "#",
  ".rb": "#",
  ".sh": "#",
  ".bash": "#",
  ".zsh": "#",
  ".yaml": "#",
  ".yml": "#",
  ".toml": "#",
  ".pl": "#",
  ".r": "#"
});

// Extract the lower-cased extension (including the leading dot) of a file path.
// Returns "" when the basename has no extension.
export function fileExtension(filePath: string): string {
  const slash = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
  const base = slash >= 0 ? filePath.slice(slash + 1) : filePath;
  const dot = base.lastIndexOf(".");
  if (dot <= 0) {
    // No dot, or a leading-dot dotfile (e.g. ".gitignore") -> no extension.
    return "";
  }
  return base.slice(dot).toLowerCase();
}

// Resolve the configured line-comment prefix for a file, or null when the
// extension is not configured (the file simply cannot carry markers).
//
// `contents` is optional. When a file has no extension it can still carry
// markers if it is a shebang script (e.g. an extensionless `hooks/session-start`
// bash hook): such scripts are overwhelmingly `#`-comment languages, so a
// leading `#!` resolves to `#`. Without contents an extensionless file stays
// null, exactly as before.
export function resolveCommentPrefix(
  filePath: string,
  config?: CommentPrefixConfig,
  contents?: string
): string | null {
  const ext = fileExtension(filePath);
  if (ext === "") {
    if (contents !== undefined && contents.startsWith("#!")) {
      return "#";
    }
    return null;
  }
  const override = config?.extensions?.[ext];
  if (override !== undefined) {
    return override;
  }
  const fromDefault = DEFAULT_COMMENT_PREFIXES[ext];
  return fromDefault ?? null;
}
