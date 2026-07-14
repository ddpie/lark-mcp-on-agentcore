// Pure parsing/classification helpers for the build-time tool-catalog generator.
//
// Extracted from generate-tools.js so they can be unit-tested directly:
// generate-tools.js runs top-level code (spawns lark-cli, writes files) on
// require, so it cannot be imported in tests. Keeping these side-effect-free
// functions here is the single source of truth — tests import this module, the
// generator requires it, and the two can never drift.

// Flags hidden from the LLM-facing schema:
// - yes / dry-run / jq: lark-cli wrapper concerns, not user intent.
//   server.js adds --yes itself when needed (gated by supportsYes).
const HIDDEN_FLAGS = new Set(['yes', 'dry-run', 'jq']);

// cobra renders a value flag as `--name <type-token>   <description>` and a
// boolean as `--name   <description>` with NO token. The two gaps differ: the
// name→token gap is a single space, the token→description gap is 2+ spaces of
// alignment padding. `parseFlags`'s greedy `\s+` collapses the name→token gap,
// but the token→description gap survives at the START of `rest` — so leading
// text up to the first 2+ space run is the TYPE TOKEN (the flag takes a value),
// and the absence of any 2+ space run means the flag is a boolean switch. We do
// NOT whitelist the token: lark-cli >=1.0.60 renders composite/JSON flags with
// an EXAMPLE as the token (`+table-put`, `[["alice",95]]`, `A1:Z200`,
// `{ top: {...}, bottom: ... }`, `[{"column":"x"}, ...]`) rather than the bare
// word `string`; a whitelist misread those as boolean and server.js dropped
// their JSON payload. The example may contain INTERNAL single spaces, so the
// token runs up to the first 2+ space gap, not the first space. Only NUMBER
// tokens need recognizing; every other value-taking flag is a string.
const NUMBER_TYPE_TOKENS = new Set(['int', 'int8', 'int16', 'int32', 'int64', 'uint', 'uint8', 'uint16', 'uint32', 'uint64', 'float', 'float32', 'float64', 'count']);

// Resolve a flag's JSON-schema type from the text following its name (`rest`).
// The type token is everything up to the first 2+ space description gap: NUMBER
// tokens → number, anything else → string (covers real type tokens like
// `string`/`duration`, single- and multi-word example tokens, and the XOR
// `--other-flag` mutual-exclusivity hint). No 2+ space gap → cobra omitted the
// token → boolean switch.
function flagTypeFromRest(rest) {
  const token = rest.match(/^(.+?)\s{2,}/)?.[1];
  if (!token) return 'boolean';
  if (NUMBER_TYPE_TOKENS.has(token)) return 'number';
  return 'string';
}

function parseFlags(helpText) {
  const flags = [];
  let supportsYes = false;
  const lines = helpText.split('\n');
  for (const line of lines) {
    const m = line.match(/^\s+--(\S+)\s+(.+)/);
    if (!m) continue;
    const [, rawName, rest] = m;
    const name = rawName;
    if (name.includes(' ')) continue;
    if (name === 'yes') { supportsYes = true; continue; }
    if (HIDDEN_FLAGS.has(name)) continue;
    let type = flagTypeFromRest(rest);
    // A `(default: false/true)` annotation is an explicit boolean signal even if
    // some other leading token were present.
    if (rest.toLowerCase().includes('(default: false)') || rest.toLowerCase().includes('(default: true)')) type = 'boolean';
    const required = rest.includes('(required)');
    const enumMatch = rest.match(/\(enum:\s*([^)]+)\)/);
    const enumValues = enumMatch ? enumMatch[1].split(',').map(s => s.trim()) : undefined;
    const description = rest.replace(/\s*\(required\)/, '').replace(/\s*\(default:[^)]+\)/, '').replace(/\s*\(enum:[^)]+\)/, '').trim();
    flags.push({ name, type, description, required, ...(enumValues && { enum: enumValues }) });
  }
  return { flags, supportsYes };
}

// Parse a service's `lark-cli <service> --help` output for its shortcut commands.
// "Available Commands:" mixes three line shapes:
//   `+cmd`              — classic shortcuts (always real tools)
//   `resource-x`        — no-plus shortcuts (lark-cli 1.0.55 docs resource-*)
//   `user_mailbox.msgs` — no-plus RAW-API resource groups; NOT shortcuts (the
//                         raw-API loop descends into these for lark_invoke)
// `+cmd` lines are always shortcuts. A no-plus line is a shortcut ONLY when it is
// in `knownNoPlus` — the set of no-plus shortcut commands for this service taken
// from shortcut-scopes.json (extracted from upstream source, the authoritative
// list). Without that gate, raw-API resource groups would be mis-registered as
// broken leaf shortcuts. Both real forms are routable: server.js passes
// def.command verbatim and toToolName strips an optional leading '+'.
// Only lines inside the section count: cobra wraps service help with 2-space-
// indented prose ("Start here ...") that would otherwise be misparsed, and the
// Flags: block (`-h, --help`) must be skipped. A blank line ends the section.
function parseShortcuts(helpText, knownNoPlus = new Set()) {
  const shortcuts = [];
  let inSection = false;
  for (const line of helpText.split('\n')) {
    if (/^[A-Za-z].*:\s*$/.test(line)) { // section header like "Available Commands:"
      inSection = /^Available Commands:/.test(line);
      continue;
    }
    if (!inSection) continue;
    if (/^\s*$/.test(line)) { inSection = false; continue; } // blank line ends section
    // command token: a +shortcut, or a lowercase no-plus command (letters, digits,
    // hyphens, dots). Excludes flag lines like `-h, --help` (start with '-').
    const m = line.match(/^\s{2,4}(\+[a-z][a-z0-9_.-]*|[a-z][a-z0-9_.-]*)\s+(.+)/);
    if (!m) continue;
    const command = m[1];
    if (!command.startsWith('+') && !knownNoPlus.has(command)) continue;
    shortcuts.push({ command, description: m[2].trim() });
  }
  return shortcuts;
}

// Section headers of the per-command "affordance" guidance block that lark-cli
// (since 1.0.60) renders INTO `--help` output, below the authoritative `Risk:`
// line. Its free prose ("unlike risk: write commands…", "Avoid when … this is
// destructive") would poison a naive whole-text substring scan, so risk
// detection must ignore it: match the Risk line at line-start, and apply the
// keyword fallback only to the text ABOVE the first affordance header.
const AFFORDANCE_SECTION_RE = /\n(?=(?:When to use|Avoid when|Prerequisites|Tips|Examples):)/;

function detectRisk(helpText, commandName) {
  // Authoritative signal: lark-cli emits a `Risk:` line per command. Anchor to
  // line-start and return on first hit so affordance prose that merely *mentions*
  // "risk: write" cannot override (or downgrade) the real classification.
  for (const line of helpText.split('\n')) {
    const m = line.match(/^\s*Risk:\s*(high-risk-write|write|read)\b/i);
    if (m) return m[1].toLowerCase();
  }
  // Fallback (no Risk line): name/keyword heuristics, scanning only the text
  // before the affordance block so its prose can't trip the `destructive` keyword.
  const lower = helpText.split(AFFORDANCE_SECTION_RE)[0].toLowerCase();
  if (lower.includes('destructive') || commandName.includes('delete') || commandName.includes('remove')) return 'high-risk-write';
  if (commandName.includes('create') || commandName.includes('send') || commandName.includes('update') || commandName.includes('patch')) return 'write';
  return 'read';
}

module.exports = { parseFlags, detectRisk, parseShortcuts };
