#!/usr/bin/env bash
# scripts/test.sh — single entry point for all tests in this repo.
#
# Tiers (can be selected individually):
#   --unit      vitest unit tests (no AWS, no docker, fast)
#   --audit     scripts/audit-tools.sh (catalog structure, needs AWS or --catalog)
#   --e2e       scripts/test-e2e.sh (live OAuth + Runtime, needs deployed stack)
#   --typecheck tsc --noEmit on infra
#   --lint      bash -n on shell scripts
#   --all       run everything (default)
#
# Each tier exits non-zero on failure; the overall exit code is non-zero if
# any selected tier failed.
#
# Examples:
#   ./scripts/test.sh                  # everything
#   ./scripts/test.sh --unit --lint    # offline checks only
#   ./scripts/test.sh --audit --catalog generated-tools.json
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
hdr() { echo -e "\n${CYAN}══════════════════════════════════════════"; echo -e " $1"; echo -e "══════════════════════════════════════════${NC}"; }
ok()  { echo -e "${GREEN}✓ $1 PASSED${NC}"; }
bad() { echo -e "${RED}✗ $1 FAILED (exit $2)${NC}"; }

DO_UNIT=0; DO_AUDIT=0; DO_E2E=0; DO_TYPECHECK=0; DO_LINT=0
AUDIT_ARGS=()
E2E_ARGS=()

if [ $# -eq 0 ]; then
  DO_UNIT=1; DO_AUDIT=1; DO_E2E=1; DO_TYPECHECK=1; DO_LINT=1
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --unit)      DO_UNIT=1; shift ;;
    --audit)     DO_AUDIT=1; shift ;;
    --e2e)       DO_E2E=1; shift ;;
    --typecheck) DO_TYPECHECK=1; shift ;;
    --lint)      DO_LINT=1; shift ;;
    --all)       DO_UNIT=1; DO_AUDIT=1; DO_E2E=1; DO_TYPECHECK=1; DO_LINT=1; shift ;;
    --catalog|--image|--region) AUDIT_ARGS+=("$1" "$2"); shift 2 ;;
    --runtime-arn|--oauth-endpoint|--user-id) E2E_ARGS+=("$1" "$2"); shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

declare -a RESULTS
run_tier() {
  local name="$1"; shift
  hdr "$name"
  if "$@"; then
    ok "$name"
    RESULTS+=("${GREEN}✓${NC} $name")
  else
    local rc=$?
    bad "$name" "$rc"
    RESULTS+=("${RED}✗${NC} $name (exit $rc)")
    OVERALL=1
  fi
}

OVERALL=0

[ "$DO_LINT" = 1 ] && run_tier "lint (bash -n on scripts/*.sh)" bash -c '
  for f in "'"$ROOT"'"/scripts/*.sh; do bash -n "$f" || exit 1; done
'
[ "$DO_TYPECHECK" = 1 ] && run_tier "typecheck (tsc --noEmit)" bash -c "cd '$ROOT/infra' && npx tsc --noEmit"
[ "$DO_UNIT" = 1 ] && run_tier "unit (vitest)" bash -c "cd '$ROOT' && npm test --silent"
[ "$DO_AUDIT" = 1 ] && run_tier "audit (catalog structure)" "$ROOT/scripts/audit-tools.sh" "${AUDIT_ARGS[@]}"
[ "$DO_E2E" = 1 ] && run_tier "e2e (live OAuth + Runtime)" "$ROOT/scripts/test-e2e.sh" "${E2E_ARGS[@]}"

echo ""
echo -e "${CYAN}═══════ Summary ═══════${NC}"
for r in "${RESULTS[@]}"; do echo -e "  $r"; done
exit "$OVERALL"
