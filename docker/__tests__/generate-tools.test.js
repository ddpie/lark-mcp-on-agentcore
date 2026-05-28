import { describe, it, expect } from 'vitest';

// Copy of detectRisk from generate-tools.js (can't require it directly as it runs top-level code)
function detectRisk(helpText, commandName) {
  const lower = helpText.toLowerCase();
  if (lower.includes('risk: high-risk-write')) return 'high-risk-write';
  if (lower.includes('risk: write')) return 'write';
  if (lower.includes('risk: read')) return 'read';
  if (lower.includes('destructive') || commandName.includes('delete') || commandName.includes('remove')) return 'high-risk-write';
  if (commandName.includes('create') || commandName.includes('send') || commandName.includes('update') || commandName.includes('patch')) return 'write';
  return 'read';
}

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
