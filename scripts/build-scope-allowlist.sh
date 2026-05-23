#!/usr/bin/env bash
# Regenerate lambda/token-refresh-shim/scope-allowlist.ts from
# docker/shortcut-scopes.json + config/oauth-scopes.json.
# Run after upgrading lark-cli or editing the default OAuth scope set.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/lambda/token-refresh-shim/scope-allowlist.ts"

python3 << PYEOF > "$OUT"
import json, sys
sc = json.load(open("${ROOT}/docker/shortcut-scopes.json"))["shortcuts"]
oauth = json.load(open("${ROOT}/config/oauth-scopes.json"))
all_scopes = set()
for entry in sc:
    for s in entry.get("scopes", []) or []:
        all_scopes.add(s)
for s in oauth:
    all_scopes.add(s)
print("// Auto-generated from docker/shortcut-scopes.json + config/oauth-scopes.json.")
print("// Regenerate with: scripts/build-scope-allowlist.sh")
print("// Limits incremental-auth \`extra_scope=\` to scopes the deployment knows about,")
print("// preventing attackers from broadening the consent screen via a phishing link.")
print("export const SCOPE_ALLOWLIST: ReadonlySet<string> = new Set([")
for s in sorted(all_scopes):
    print(f"  {json.dumps(s)},")
print("]);")
PYEOF

echo "Wrote ${OUT} ($(wc -l <"$OUT") lines)"
