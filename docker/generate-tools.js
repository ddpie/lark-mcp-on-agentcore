#!/usr/bin/env node
// Generates tool definitions from lark-cli at Docker build time.
// Mirrors the logic of lark-cli-mcp-wrapper/src/generate.ts

const { execFileSync } = require('child_process');
const fs = require('fs');

const OUTPUT = '/app/generated-tools.json';

function run(cmd, ...args) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf-8', timeout: 15000, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch { return ''; }
}

function getVersion() {
  const output = run('lark-cli', '--version');
  const match = output.match(/[\d.]+/);
  return match ? match[0] : 'unknown';
}

function parseFlags(helpText) {
  const flags = [];
  const lines = helpText.split('\n');
  for (const line of lines) {
    const m = line.match(/^\s+--(\S+)\s+(.+)/);
    if (!m) continue;
    const [, rawName, rest] = m;
    let name = rawName;
    let type = 'string';
    if (name.includes(' ')) continue;
    if (rest.toLowerCase().includes('(default: false)') || rest.toLowerCase().includes('(default: true)')) type = 'boolean';
    const required = rest.includes('(required)');
    const enumMatch = rest.match(/\(enum:\s*([^)]+)\)/);
    const enumValues = enumMatch ? enumMatch[1].split(',').map(s => s.trim()) : undefined;
    const description = rest.replace(/\s*\(required\)/, '').replace(/\s*\(default:[^)]+\)/, '').replace(/\s*\(enum:[^)]+\)/, '').trim();
    flags.push({ name, type, description, required, ...(enumValues && { enum: enumValues }) });
  }
  return flags;
}

function detectRisk(helpText, commandName) {
  const lower = helpText.toLowerCase();
  if (lower.includes('[high-risk-write]') || lower.includes('destructive') || commandName.includes('delete') || commandName.includes('remove')) return 'high-risk-write';
  if (lower.includes('[write]') || commandName.includes('create') || commandName.includes('send') || commandName.includes('update') || commandName.includes('patch')) return 'write';
  return 'read';
}

function discoverServices() {
  const help = run('lark-cli', '--help');
  const services = [];
  const skipServices = new Set(['api', 'auth', 'config', 'doctor', 'help', 'profile', 'schema', 'update', 'event', 'skill']);
  for (const line of help.split('\n')) {
    const m = line.match(/^\s{2,4}(\w+)\s/);
    if (m && !skipServices.has(m[1])) services.push(m[1]);
  }
  return services;
}

function discoverShortcuts(service) {
  const help = run('lark-cli', service, '--help');
  const shortcuts = [];
  for (const line of help.split('\n')) {
    const m = line.match(/^\s{2,4}(\+\S+)\s+(.+)/);
    if (m) shortcuts.push({ command: m[1], description: m[2].trim() });
  }
  return { shortcuts, help };
}

console.log('Generating tool catalog from lark-cli...');
const version = getVersion();
console.log(`lark-cli version: ${version}`);

const services = discoverServices();
console.log(`Found ${services.length} services`);

const tools = [];
for (const service of services) {
  const { shortcuts } = discoverShortcuts(service);
  for (const { command, description } of shortcuts) {
    const cmdHelp = run('lark-cli', service, command, '--help');
    const flags = parseFlags(cmdHelp);
    const risk = detectRisk(cmdHelp, command);
    tools.push({ service, command, description, risk, flags });
  }
}

const output = { _larkCliVersion: version, tools };
fs.writeFileSync(OUTPUT, JSON.stringify(output));
console.log(`Saved ${tools.length} tools to ${OUTPUT}`);
