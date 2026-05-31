import { describe, it, expect } from 'vitest';
// Import the REAL helpers (generate-tools.js itself runs top-level code on
// require — spawns lark-cli, writes files — so the pure functions live in
// generate-tools-lib.js and the generator requires them. Single source of truth.)
import { detectRisk, parseFlags } from '../generate-tools-lib.js';

describe('detectRisk', () => {
  it('detects "Risk: write" from help text', () => {
    const help = 'Upload a local file to Drive\n\nUsage:\n  lark-cli drive +upload [flags]\n\nRisk: write';
    expect(detectRisk(help, '+upload')).toBe('write');
  });

  it('detects "Risk: read" from help text', () => {
    const help = 'View calendar agenda\n\nRisk: read';
    expect(detectRisk(help, '+agenda')).toBe('read');
  });

  it('detects "Risk: high-risk-write" from help text', () => {
    const help = 'Delete a group chat permanently\n\nRisk: high-risk-write';
    expect(detectRisk(help, '+chat-delete')).toBe('high-risk-write');
  });

  it('prefers explicit Risk line over command name heuristic', () => {
    // Command name says "create" (heuristic → write) but help says "read"
    const help = 'Create a read-only view\n\nRisk: read';
    expect(detectRisk(help, '+create-view')).toBe('read');
  });

  it('falls back to command name heuristic when no Risk line', () => {
    expect(detectRisk('some help text', '+create')).toBe('write');
    expect(detectRisk('some help text', '+send')).toBe('write');
    expect(detectRisk('some help text', '+update')).toBe('write');
    expect(detectRisk('some help text', '+patch')).toBe('write');
    expect(detectRisk('some help text', '+delete')).toBe('high-risk-write');
    expect(detectRisk('some help text', '+remove')).toBe('high-risk-write');
  });

  it('defaults to read when no Risk line and no heuristic match', () => {
    expect(detectRisk('some help text', '+list')).toBe('read');
    expect(detectRisk('some help text', '+search')).toBe('read');
    expect(detectRisk('some help text', '+get')).toBe('read');
  });

  it('handles "destructive" keyword in help text', () => {
    const help = 'This is a destructive operation.';
    expect(detectRisk(help, '+some-cmd')).toBe('high-risk-write');
  });

  it('case-insensitive match for Risk line', () => {
    expect(detectRisk('RISK: WRITE', '+foo')).toBe('write');
    expect(detectRisk('risk: HIGH-RISK-WRITE', '+foo')).toBe('high-risk-write');
  });

  // Regression: these were previously misdetected as "read"
  it('correctly detects write for drive +upload', () => {
    const help = 'Upload a local file to Drive\n\nUsage:\n  lark-cli drive +upload [flags]\n\nFlags:\n      --file string\n\nRisk: write';
    expect(detectRisk(help, '+upload')).toBe('write');
  });

  it('correctly detects write for sheets +write', () => {
    const help = 'Write to spreadsheet cells\n\nRisk: write';
    expect(detectRisk(help, '+write')).toBe('write');
  });

  it('correctly detects write for task +complete', () => {
    const help = 'Mark a task as complete\n\nRisk: write';
    expect(detectRisk(help, '+complete')).toBe('write');
  });
});

describe('parseFlags', () => {
  it('parses a required string flag', () => {
    const { flags, supportsYes } = parseFlags('Flags:\n      --chat-id string   Target chat ID (required)');
    expect(supportsYes).toBe(false);
    expect(flags).toHaveLength(1);
    expect(flags[0]).toMatchObject({ name: 'chat-id', type: 'string', required: true });
    // Characterization: lark-cli help puts the type token before the description, and the
    // parser keeps it in the description text. Locking in current shipped behavior.
    expect(flags[0].description).toBe('string   Target chat ID');
    expect(flags[0].enum).toBeUndefined();
  });

  it('detects a boolean flag from (default: false/true)', () => {
    const { flags } = parseFlags('Flags:\n      --page-all   Fetch all pages (default: false)');
    expect(flags[0]).toEqual({ name: 'page-all', type: 'boolean', description: 'Fetch all pages', required: false });
  });

  it('extracts enum values and strips the (enum: ...) annotation from the description', () => {
    const { flags } = parseFlags('Flags:\n      --format string   Output format (enum: json,csv,yaml)');
    expect(flags[0].enum).toEqual(['json', 'csv', 'yaml']);
    expect(flags[0].description).toBe('string   Output format');
  });

  it('treats --yes as supportsYes and excludes it from flags', () => {
    const { flags, supportsYes } = parseFlags('Flags:\n      --yes   Skip confirmation\n      --summary string   Title');
    expect(supportsYes).toBe(true);
    expect(flags.map(f => f.name)).toEqual(['summary']);
  });

  it('drops hidden flags (dry-run, jq) but keeps others', () => {
    const { flags } = parseFlags('Flags:\n      --dry-run   preview\n      --jq string   filter\n      --keep string   z');
    expect(flags.map(f => f.name)).toEqual(['keep']);
  });

  it('strips (required), (default:), and (enum:) annotations together', () => {
    const { flags } = parseFlags('Flags:\n      --mode string   The mode (required) (default: a) (enum: a,b)');
    expect(flags[0]).toMatchObject({ name: 'mode', required: true, enum: ['a', 'b'] });
    expect(flags[0].description).toBe('string   The mode');
  });

  // Regression: cobra boolean flags render with NO type token and NO default
  // annotation (e.g. `--has-chatted   restrict to users...`). They were being
  // misclassified as `string`, so server.js emitted `--has-chatted true`, which
  // lark-cli rejects as an unexpected positional arg. A flag with no type token
  // is a boolean.
  it('detects a boolean flag from the ABSENCE of a type token', () => {
    const { flags } = parseFlags('Flags:\n      --has-chatted   restrict to users you have chatted with');
    expect(flags[0]).toMatchObject({ name: 'has-chatted', type: 'boolean', required: false });
  });

  it('classifies an int type token as number', () => {
    const { flags } = parseFlags('Flags:\n      --page-size int   rows per request, 1-30');
    expect(flags[0]).toMatchObject({ name: 'page-size', type: 'number' });
  });

  it('classifies a float type token as number', () => {
    const { flags } = parseFlags('Flags:\n      --ratio float   scale factor');
    expect(flags[0]).toMatchObject({ name: 'ratio', type: 'number' });
  });

  it('keeps string-like type tokens (string, stringArray, duration) as string', () => {
    expect(parseFlags('Flags:\n      --tags stringArray   labels').flags[0]).toMatchObject({ name: 'tags', type: 'string' });
    expect(parseFlags('Flags:\n      --wait duration   timeout').flags[0]).toMatchObject({ name: 'wait', type: 'string' });
  });

  it('still treats a boolean with (default: false) as boolean (no type token)', () => {
    const { flags } = parseFlags('Flags:\n      --page-all   Fetch all pages (default: false)');
    expect(flags[0]).toMatchObject({ name: 'page-all', type: 'boolean' });
  });

  it('returns no flags when there is no flag section', () => {
    expect(parseFlags('Just a description, no flags here')).toEqual({ flags: [], supportsYes: false });
  });

  it('ignores lines that are not indented flag definitions', () => {
    // Usage lines / prose mentioning --foo without the leading-whitespace + "-- " shape
    const { flags } = parseFlags('Usage:\n  lark-cli im +send --chat-id <id>\n\nSend a message');
    expect(flags).toEqual([]);
  });
});
