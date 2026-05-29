#!/usr/bin/env node
// Generates tool definitions from lark-cli at Docker build time.
// Mirrors the logic of lark-cli-mcp-wrapper/src/generate.ts

const { execFileSync } = require('child_process');
const fs = require('fs');
const { parseFlags, detectRisk } = require('./generate-tools-lib');

const OUTPUT = '/app/generated-tools.json';
const SCOPES_FILE = '/app/shortcut-scopes.json';

const BUILD_ENV = {
  ...process.env,
  NO_COLOR: '1',
  LARKSUITE_CLI_APP_ID: process.env.LARKSUITE_CLI_APP_ID || 'build',
  LARKSUITE_CLI_APP_SECRET: process.env.LARKSUITE_CLI_APP_SECRET || 'build',
  LARKSUITE_CLI_USER_ACCESS_TOKEN: process.env.LARKSUITE_CLI_USER_ACCESS_TOKEN || 'build',
  LARKSUITE_CLI_BRAND: process.env.LARKSUITE_CLI_BRAND || 'feishu',
};

function run(cmd, ...args) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf-8', timeout: 15000, env: BUILD_ENV, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch { return ''; }
}

function getVersion() {
  const output = run('lark-cli', '--version');
  const match = output.match(/[\d.]+/);
  return match ? match[0] : 'unknown';
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

// Load scope mapping from source-extracted data
let scopeMap = {};
let scopeMapVersion = 'unknown';
if (fs.existsSync(SCOPES_FILE)) {
  const raw = JSON.parse(fs.readFileSync(SCOPES_FILE, 'utf8'));
  const scopeData = raw.shortcuts || raw;
  if (raw._meta) scopeMapVersion = raw._meta.lark_cli_version || 'unknown';
  for (const entry of scopeData) {
    const key = `${entry.service}:${entry.command}`;
    scopeMap[key] = entry.scopes || [];
  }
  console.log(`Scope map loaded: ${Object.keys(scopeMap).length} entries (lark-cli ${scopeMapVersion})`);
}

console.log('Generating tool catalog from lark-cli...');
const version = getVersion();
console.log(`lark-cli version: ${version}`);

const services = discoverServices();
console.log(`Found ${services.length} services`);

const tools = [];
let scopeMapped = 0;
for (const service of services) {
  const { shortcuts } = discoverShortcuts(service);
  for (const { command, description } of shortcuts) {
    const cmdHelp = run('lark-cli', service, command, '--help');
    const { flags, supportsYes } = parseFlags(cmdHelp);
    const risk = detectRisk(cmdHelp, command);
    const scopes = scopeMap[`${service}:${command}`] || [];
    if (scopes.length > 0) scopeMapped++;
    tools.push({ service, command, description, risk, flags, ...(supportsYes && { supportsYes: true }), ...(scopes.length > 0 && { scopes }) });
  }
}

const output = { _larkCliVersion: version, _scopeMapVersion: scopeMapVersion, tools };
fs.writeFileSync(OUTPUT, JSON.stringify(output));
console.log(`Saved ${tools.length} tools to ${OUTPUT} (${scopeMapped} with scope info)`);

const unmapped = tools.length - scopeMapped;
if (unmapped > 5) {
  console.warn(`\n⚠ WARNING: ${unmapped} tools have no scope mapping. Incremental authorization will not work for these tools.`);
  console.warn(`  This usually means lark-cli has added new commands not covered by shortcut-scopes.json (built for ${scopeMapVersion}).`);
  console.warn(`  To fix: pin lark-cli to the tested version in Dockerfile:`);
  console.warn(`    ARG LARK_CLI_VERSION=${scopeMapVersion}`);
  console.warn(`  Or contact: ddpie.flea@gmail.com for an updated scope map.\n`);
}

