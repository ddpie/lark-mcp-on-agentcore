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

function parseFlags(helpText) {
  const flags = [];
  let supportsYes = false;
  const lines = helpText.split('\n');
  for (const line of lines) {
    const m = line.match(/^\s+--(\S+)\s+(.+)/);
    if (!m) continue;
    const [, rawName, rest] = m;
    const name = rawName;
    let type = 'string';
    if (name.includes(' ')) continue;
    if (name === 'yes') { supportsYes = true; continue; }
    if (HIDDEN_FLAGS.has(name)) continue;
    if (rest.toLowerCase().includes('(default: false)') || rest.toLowerCase().includes('(default: true)')) type = 'boolean';
    const required = rest.includes('(required)');
    const enumMatch = rest.match(/\(enum:\s*([^)]+)\)/);
    const enumValues = enumMatch ? enumMatch[1].split(',').map(s => s.trim()) : undefined;
    const description = rest.replace(/\s*\(required\)/, '').replace(/\s*\(default:[^)]+\)/, '').replace(/\s*\(enum:[^)]+\)/, '').trim();
    flags.push({ name, type, description, required, ...(enumValues && { enum: enumValues }) });
  }
  return { flags, supportsYes };
}

function detectRisk(helpText, commandName) {
  const lower = helpText.toLowerCase();
  // Prefer explicit "Risk:" line from lark-cli help output
  if (lower.includes('risk: high-risk-write')) return 'high-risk-write';
  if (lower.includes('risk: write')) return 'write';
  if (lower.includes('risk: read')) return 'read';
  // Fallback: heuristics from command name
  if (lower.includes('destructive') || commandName.includes('delete') || commandName.includes('remove')) return 'high-risk-write';
  if (commandName.includes('create') || commandName.includes('send') || commandName.includes('update') || commandName.includes('patch')) return 'write';
  return 'read';
}

module.exports = { parseFlags, detectRisk };
