#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "" >&2
  echo "  bash 4+ required (current: ${BASH_VERSION})" >&2
  echo "" >&2
  if command -v brew &>/dev/null; then
    NEW_BASH="$(brew --prefix)/bin/bash"
    if [ -x "$NEW_BASH" ] && [[ "$("$NEW_BASH" -c 'echo ${BASH_VERSINFO[0]}')" -ge 4 ]]; then
      echo "  Found ${NEW_BASH}, restarting..." >&2
      exec "$NEW_BASH" "$0" "$@"
    fi
    printf "  Install bash 4+ via Homebrew and continue? (Y/n) " >&2
    read -r _ans </dev/tty 2>/dev/null || _ans="y"
    if [[ ! "${_ans:-y}" =~ ^[nN] ]]; then
      brew install bash
      echo "  Restarting with ${NEW_BASH}..." >&2
      exec "$NEW_BASH" "$0" "$@"
    fi
  fi
  echo "  Manual upgrade:" >&2
  echo "    macOS:  brew install bash" >&2
  echo "    Linux:  sudo apt-get install -y bash  (or yum install bash)" >&2
  echo "" >&2
  echo "  Then re-run:" >&2
  echo "    /opt/homebrew/bin/bash ./scripts/deploy.sh" >&2
  echo "" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_DIR="${PROJECT_DIR}/.local"
mkdir -p "$LOCAL_DIR"

# --app <slug> / --alias <name>: multi-app support. Resolve all per-app physical
# names from the slug (empty slug = default sentinel = today's byte-identical
# names). See scripts/lib/slug.sh and .claude/specs/2026-06-07-multi-app-*.
APP_SLUG="${APP_SLUG:-}"
APP_ALIAS="${APP_ALIAS:-}"
AUTO_YES=0
_args=("$@")
for ((_i=0; _i<${#_args[@]}; _i++)); do
  case "${_args[_i]}" in
    --yes|-y) AUTO_YES=1 ;;
    --app)    APP_SLUG="${_args[_i+1]:-}"; _i=$((_i+1)) ;;
    --app=*)  APP_SLUG="${_args[_i]#--app=}" ;;
    --alias)  APP_ALIAS="${_args[_i+1]:-}"; _i=$((_i+1)) ;;
    --alias=*) APP_ALIAS="${_args[_i]#--alias=}" ;;
  esac
done

# shellcheck source=lib/slug.sh
source "${SCRIPT_DIR}/lib/slug.sh"
if ! resolve_slug "$APP_SLUG"; then
  exit 1
fi
# resolve_slug exports: SLUG SFX RUNTIME_NAME FEISHU_SECRET SECRET_USERS_PREFIX
# STATE_PARAM OAUTH_SECRET_PARAM WEBHOOK_SSM_NAME CODE_TABLE OPENID_TABLE
# OAUTH_CLIENT_ID OAUTH_STACK RUNTIME_STACK WAF_STACK

# Per-slug deploy-config so deploying app B never clobbers app A's saved config.
# Default slug keeps the original .local/deploy-config path (backward compat).
if [ -n "$SLUG" ]; then
  APP_LOCAL_DIR="${LOCAL_DIR}/apps/${SLUG}"
  mkdir -p "$APP_LOCAL_DIR"
  DEPLOY_CONFIG="${APP_LOCAL_DIR}/deploy-config"
else
  DEPLOY_CONFIG="${LOCAL_DIR}/deploy-config"
fi

# App registry + HARD alias uniqueness (only for named apps; the default app has
# no alias). Claim the alias ATOMICALLY before creating any resource, so a
# collision aborts cleanly with no half-built stack.
APPS_REGISTRY="${LOCAL_DIR}/apps.json"
export APPS_REGISTRY
if [ -n "$SLUG" ]; then
  # shellcheck source=lib/registry.sh
  source "${SCRIPT_DIR}/lib/registry.sh"
  [ -z "$APP_ALIAS" ] && APP_ALIAS="$SLUG"   # default the alias to the slug
  if ! claim_alias "$SLUG" "$APP_ALIAS"; then
    echo "  ERROR: alias '${APP_ALIAS}' is already used by another app. Pick a unique --alias." >&2
    exit 1
  fi
fi

if [ "$AUTO_YES" = "1" ]; then
  if [ ! -f "$DEPLOY_CONFIG" ]; then
    echo "  ERROR: --yes requires a previous deployment config (${DEPLOY_CONFIG})." >&2
    echo "  Run once interactively first (for app '${SLUG:-default}'), then use --yes." >&2
    exit 1
  fi
  # Load all saved config values as env vars
  set -a
  # shellcheck source=/dev/null
  source "$DEPLOY_CONFIG"
  set +a
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Arrow-key interactive picker. Usage: pick RESULT_VAR "label1" "label2" ...
# Optional: set PICK_DEFAULT=N (1-based) before calling to pre-select.
pick() {
  local _var="$1"; shift
  local -a _items=("$@")
  local _count=${#_items[@]}
  local _sel=${PICK_DEFAULT:-1}
  (( _sel < 1 || _sel > _count )) && _sel=1

  # Non-interactive: auto-select default
  if [ "$AUTO_YES" = "1" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
    eval "$_var=\"\${_items[\$((_sel-1))]}\""
    unset PICK_DEFAULT
    return
  fi

  # Drain any buffered input to prevent stray Enter from auto-selecting
  while IFS= read -r -t 0.05 _ </dev/tty 2>/dev/null; do :; done

  # Hide cursor; restore on interrupt and exit
  trap 'printf "\033[?25h" >/dev/tty; exit 130' INT
  printf '\033[?25l' >/dev/tty

  _pick_draw() {
    local i
    for ((i=1; i<=_count; i++)); do
      if ((i == _sel)); then
        printf '\033[36m  ❯ %s\033[0m\n' "${_items[$((i-1))]}" >/dev/tty
      else
        printf '    %s\n' "${_items[$((i-1))]}" >/dev/tty
      fi
    done
  }

  _pick_draw
  while true; do
    local _key
    IFS= read -rsn1 _key </dev/tty
    if [[ "$_key" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 _key </dev/tty
      case "$_key" in
        '[A') (( _sel > 1 )) && (( _sel-- )) ;;       # Up
        '[B') (( _sel < _count )) && (( _sel++ )) ;;  # Down
      esac
      printf '\033[%dA' "$_count" >/dev/tty
      _pick_draw
    elif [[ -z "$_key" || "$_key" == $'\n' ]]; then
      break
    fi
  done

  # Show cursor and restore trap
  printf '\033[?25h' >/dev/tty
  trap - INT
  eval "$_var=\"\${_items[\$((_sel-1))]}\""
  unset PICK_DEFAULT
}

# Language selection (only ask if not already set by install.sh or saved config)
if [ -z "${LARK_LANG:-}" ] && [ -f "$DEPLOY_CONFIG" ]; then
  SAVED_LANG=$(grep '^LARK_LANG=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  [ -n "$SAVED_LANG" ] && export LARK_LANG="$SAVED_LANG"
fi
if [ -z "${LARK_LANG:-}" ]; then
  echo ""
  echo "  Select language / 选择语言:"
  echo ""
  pick _LANG_PICK "中文" "English"
  case "$_LANG_PICK" in
    English) export LARK_LANG="en" ;;
    *) export LARK_LANG="zh" ;;
  esac
fi

# --- i18n messages (loaded from config/i18n.json) ---
if ! command -v python3 &>/dev/null; then
  echo "  ERROR: python3 is required but not found" >&2
  exit 1
fi
declare -A L
I18N_FILE="${PROJECT_DIR}/config/i18n.json"
if [ ! -f "$I18N_FILE" ]; then
  echo "  ERROR: config/i18n.json not found" >&2
  exit 1
fi
eval "$(python3 -c "
import json, sys, re
data = json.load(open(sys.argv[1]))['shell']
lang = sys.argv[2]
strings = data.get(lang, data['en'])
for k, v in strings.items():
    if not re.match(r'^[a-z][a-z0-9_]*$', k):
        print(f'ERROR: invalid i18n key: {k}', file=sys.stderr)
        sys.exit(1)
    safe = v.replace(\"'\", \"'\\\"'\\\"'\")
    print(f\"L[{k}]='{safe}'\")
" "$I18N_FILE" "$LARK_LANG")"

t() { printf "${L[$1]}" "${@:2}"; }
step() { echo -e "\n${GREEN}=== ${L[$1]} ===${NC}\n"; }
info() { echo -e "${CYAN}  $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }

# Drain any pre-typed input so a stray Enter held over from the previous prompt
# can't auto-accept the next one. Critical for confirm prompts (region, WAF,
# deploy start) where a held Enter could blow past intentional decisions.
drain_stdin() {
  if [ -t 0 ]; then
    local _discard
    while IFS= read -r -t 0.05 _discard </dev/tty 2>/dev/null; do :; done
  fi
}
prompt() {
  if [ "$AUTO_YES" = "1" ]; then return; fi
  drain_stdin; read -rp "  $1" "$2" </dev/tty;
}
ask() {
  if [ "$AUTO_YES" = "1" ]; then
    # In auto mode, keep the variable's current value (already loaded from config)
    if [ -n "${!2:-}" ]; then return; fi
    echo "  ERROR: --yes mode but no saved value for $2" >&2; exit 1
  fi
  drain_stdin; read -rp "  $1: " "$2" </dev/tty;
}

# Yes/No picker. Returns 0 for yes, 1 for no. Default is first option (yes).
# Usage: if confirm "Question?"; then ... fi
# For default=no: PICK_DEFAULT=2 confirm "Question?"
confirm() {
  local _q="$1"
  echo "  $_q"
  pick _YN "${L[yes]}" "${L[no]}"
  [[ "$_YN" == "${L[yes]}" ]]
}

cleanup() {
  if [ "${DEPLOY_STARTED:-false}" = "true" ]; then
    echo ""
    warn "${L[interrupted]}"
    info "  cd infra && npx cdk destroy --all"
    info "  ${L[or_rerun]}"
  fi
}
trap cleanup EXIT

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
printf "  ║   %-39s║\n" "${L[title]}"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# 检查环境
step check_env
DEPS_OK=true
for cmd in node docker aws python3; do
  if command -v $cmd &>/dev/null; then
    printf "  %-10s ✓\n" "$cmd"
  else
    err "Missing: ${cmd}"
    DEPS_OK=false
  fi
done

if command -v docker &>/dev/null && ! docker info &>/dev/null; then
  warn "${L[docker_not_running]}"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    info "  open -a Docker"
    open -a Docker 2>/dev/null || true
  fi
  echo ""
  info "  Waiting for Docker to start..."
  for _i in $(seq 1 30); do
    docker info &>/dev/null && break
    sleep 2
  done
  if ! docker info &>/dev/null; then
    err "${L[docker_not_running]}"
    DEPS_OK=false
  else
    info "  Docker: ✓"
  fi
fi

if ! python3 -c "import boto3" &>/dev/null; then
  err "Missing: python3 boto3 (pip3 install boto3)"
  DEPS_OK=false
fi

if [ "$DEPS_OK" = "false" ]; then
  echo ""
  warn "${L[run_install]}"
  info "bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)"
  exit 1
fi

# AWS 凭证
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  warn "${L[aws_not_configured]}"
  echo ""
  pick _AWS_PICK "aws configure  (Access Key)" "aws sso login  (SSO)" "${L[aws_retry]}"
  case "$_AWS_PICK" in
    aws\ configure*) aws configure ;;
    aws\ sso*) aws sso login ;;
    *) ;;
  esac
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  if [ -z "$ACCOUNT_ID" ]; then
    err "${L[aws_fail]}"
    exit 1
  fi
fi
# Select region BEFORE checking Secrets Manager so we query the right region.
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
PREV_REGION=""
if [ -f "$DEPLOY_CONFIG" ]; then
  PREV_REGION=$(grep '^REGION=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
fi
REGION_SELECTED=""
if [ -n "$PREV_REGION" ] && [ -t 0 ]; then
  info "$(t region_existing "$PREV_REGION")"
  if confirm "${L[region_keep]}"; then
    REGION="$PREV_REGION"
    REGION_SELECTED=1
  fi
elif [ -n "$PREV_REGION" ]; then
  REGION="$PREV_REGION"
  REGION_SELECTED=1
fi
if [ -z "$REGION_SELECTED" ]; then
  echo ""
  echo "  ${L[select_region]}"
  echo ""
  pick _REGION_PICK \
    "ap-northeast-1   Tokyo" \
    "us-west-2        Oregon" \
    "us-east-1        Virginia" \
    "ap-southeast-1   Singapore" \
    "ap-southeast-2   Sydney" \
    "ap-south-1       Mumbai" \
    "eu-west-1        Ireland" \
    "eu-central-1     Frankfurt" \
    "me-central-1     UAE" \
    "${L[manual_input]}"
  REGION=$(echo "$_REGION_PICK" | awk '{print $1}')
  if [ "$REGION" = "${L[manual_input]}" ]; then
    ask "${L[ask_region]}" REGION
  fi
fi
info "AWS Account: ${ACCOUNT_ID}"
info "Region: ${REGION}"

# 配置飞书应用
step configure_feishu

# Check if credentials already exist in Secrets Manager (from a prior deploy)
EXISTING_CREDS=""
EXISTING_APP_ID=""
if aws secretsmanager describe-secret --secret-id "$FEISHU_SECRET" --region "$REGION" &>/dev/null; then
  EXISTING_CREDS=$(aws secretsmanager get-secret-value --secret-id "$FEISHU_SECRET" --region "$REGION" \
    --query 'SecretString' --output text 2>/dev/null || echo "")
  if [ -n "$EXISTING_CREDS" ]; then
    EXISTING_APP_ID=$(echo "$EXISTING_CREDS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('appId',''))" 2>/dev/null || echo "")
  fi
fi

if [ -n "$EXISTING_APP_ID" ] && [ -z "${FEISHU_APP_ID:-}" ] && [ -z "${FEISHU_APP_SECRET:-}" ]; then
  info "$(t feishu_creds_existing "$EXISTING_APP_ID")"
  if confirm "${L[feishu_creds_keep]}"; then
    APP_SECRET=$(echo "$EXISTING_CREDS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('appSecret',''))" 2>/dev/null || echo "")
    if [ -n "$APP_SECRET" ]; then
      APP_ID="$EXISTING_APP_ID"
      info "${L[creds_valid]}"
    else
      warn "${L[app_secret_empty]}"
    fi
  fi
fi

if [ -z "${APP_ID:-}" ]; then
  echo "  ${L[feishu_creds_needed]}"
  echo "  ${L[feishu_platform]}"
  echo ""
fi

while [ -z "${APP_ID:-}" ]; do
  if [ -n "${FEISHU_APP_ID:-}" ]; then
    APP_ID="$FEISHU_APP_ID"
    info "App ID (env): ${APP_ID}"
  else
    ask "${L[ask_app_id]}" APP_ID
  fi

  if [ -z "$APP_ID" ]; then
    err "${L[app_id_empty]}"
    continue
  fi

  if [ -n "${FEISHU_APP_SECRET:-}" ]; then
    APP_SECRET="$FEISHU_APP_SECRET"
    info "App Secret (env): ***"
  else
    echo -n "  ${L[ask_app_secret]}"
    APP_SECRET=""
    while IFS= read -rsn1 ch; do
      if [[ -z "$ch" ]]; then break; fi
      if [[ "$ch" == $'\x7f' || "$ch" == $'\b' ]]; then
        if [[ -n "$APP_SECRET" ]]; then
          APP_SECRET="${APP_SECRET%?}"
          echo -ne '\b \b'
        fi
      else
        APP_SECRET+="$ch"
        echo -n '*'
      fi
    done
    echo ""
  fi

  if [ -z "$APP_SECRET" ]; then
    err "${L[app_secret_empty]}"
    continue
  fi

  echo ""
  info "App ID:     ${APP_ID}"
  info "App Secret: ${APP_SECRET:0:4}****"
  pick _CRED_CONFIRM "${L[opt_confirm]}" "${L[opt_re_enter]}" "${L[opt_cancel]}"
  case "$_CRED_CONFIRM" in
    "${L[opt_cancel]}") echo "  ${L[cancelled]}"; exit 0 ;;
    "${L[opt_re_enter]}") unset FEISHU_APP_ID FEISHU_APP_SECRET; APP_ID=""; APP_SECRET=""; continue ;;
    *)
      info "${L[verifying_creds]}"
      VERIFY_RESP=$(curl -s --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/app_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"${APP_ID}\",\"app_secret\":\"${APP_SECRET}\"}" 2>/dev/null || echo '{}')
      # `|| true`: grep returns non-zero on no match, which under `set -e -o
      # pipefail` would abort the whole deploy if Feishu returns an unexpected
      # body (e.g. VERIFY_RESP defaulted to "{}" on a curl failure). Treat a
      # missing field as "creds not verified" and re-prompt instead of crashing.
      VERIFY_CODE=$(echo "$VERIFY_RESP" | grep -o '"code":[0-9]*' | head -1 | cut -d: -f2 || true)
      if [ "${VERIFY_CODE:-}" = "0" ]; then
        info "${L[creds_valid]}"
        break
      else
        VERIFY_MSG=$(echo "$VERIFY_RESP" | grep -o '"msg":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        # shellcheck disable=SC2059
        printf "  ${L[creds_invalid]}\n" "${VERIFY_MSG:-unknown}"
        unset FEISHU_APP_ID FEISHU_APP_SECRET
        APP_ID=""; APP_SECRET=""
        continue
      fi
      ;;
  esac
done

# Previous deploy config is read inline by each prompt section below.
# Env vars always take priority over saved config.

step configure_deploy

# 自定义域名（可选）— remember previous choice
PREV_DOMAIN=""
if [ -f "$DEPLOY_CONFIG" ]; then
  PREV_DOMAIN=$(grep '^CUSTOM_DOMAIN=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
fi
if [ -z "${CUSTOM_DOMAIN+x}" ]; then
  if [ -n "$PREV_DOMAIN" ] && [ -t 0 ]; then
    echo ""
    info "$(t custom_domain_existing "$PREV_DOMAIN")"
    pick _DOMAIN_ACT "${L[keep]}" "${L[change]}" "${L[clear]}"
    case "$_DOMAIN_ACT" in
      "${L[clear]}") CUSTOM_DOMAIN="" ;;
      "${L[change]}") prompt "${L[custom_domain]}" CUSTOM_DOMAIN ;;
      *) CUSTOM_DOMAIN="$PREV_DOMAIN" ;;
    esac
  else
    echo ""
    prompt "${L[custom_domain]}" CUSTOM_DOMAIN
  fi
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
  if [[ ! "$CUSTOM_DOMAIN" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    err "Invalid domain: ${CUSTOM_DOMAIN}"
    exit 1
  fi
  info "Custom domain: ${CUSTOM_DOMAIN}"
fi

# Extra OAuth redirect hosts (comma-separated), for non-loopback clients whose
# callback host needs allowlisting. Current clients (Kiro/Claude Code/Codex) all
# use loopback so this is typically empty. Merged with CUSTOM_DOMAIN.
PREV_EXTRA=""
if [ -f "$DEPLOY_CONFIG" ]; then
  PREV_EXTRA=$(grep '^EXTRA_ALLOWED_DOMAINS=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
fi
if [ -z "${EXTRA_ALLOWED_DOMAINS+x}" ]; then
  if [ -n "$PREV_EXTRA" ] && [ -t 0 ]; then
    echo ""
    info "$(t extra_domains_existing "$PREV_EXTRA")"
    pick _EXTRA_ACT "${L[keep]}" "${L[change]}" "${L[clear]}"
    case "$_EXTRA_ACT" in
      "${L[clear]}") EXTRA_ALLOWED_DOMAINS="" ;;
      "${L[change]}") prompt "${L[extra_domains]}" EXTRA_ALLOWED_DOMAINS ;;
      *) EXTRA_ALLOWED_DOMAINS="$PREV_EXTRA" ;;
    esac
  elif [ -t 0 ]; then
    echo ""
    prompt "${L[extra_domains]}" EXTRA_ALLOWED_DOMAINS
  else
    EXTRA_ALLOWED_DOMAINS="${PREV_EXTRA}"
  fi
fi
EXTRA_ALLOWED_DOMAINS="${EXTRA_ALLOWED_DOMAINS// /}"
if [ -n "$EXTRA_ALLOWED_DOMAINS" ]; then
  if [[ ! "$EXTRA_ALLOWED_DOMAINS" =~ ^[a-zA-Z0-9._,-]+$ ]]; then
    err "Invalid EXTRA_ALLOWED_DOMAINS (comma-separated hosts): ${EXTRA_ALLOWED_DOMAINS}"
    exit 1
  fi
  info "Extra allowed redirect hosts: ${EXTRA_ALLOWED_DOMAINS}"
fi

# AWS Security Agent domain-ownership verification (optional, HTTP route method).
# Users enter the raw token(s) from the console — comma/space-separated for
# multiple agent spaces; deploy builds the {"tokens":[...]} body the doc requires.
# Input is normalized to a bare comma-joined form (no spaces) before it is saved
# to / sourced from deploy-config, so the value is always `source`-safe. Each
# token is [A-Za-z0-9_-]. Empty = disabled.
PREV_DV_TOKENS=""
if [ -f "$DEPLOY_CONFIG" ]; then
  PREV_DV_TOKENS=$(grep '^DOMAIN_VERIFICATION_TOKENS=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
fi
if [ -z "${DOMAIN_VERIFICATION_TOKENS+x}" ]; then
  if [ -n "$PREV_DV_TOKENS" ] && [ -t 0 ]; then
    echo ""
    info "$(t domain_verification_existing "$PREV_DV_TOKENS")"
    pick _DV_ACT "${L[keep]}" "${L[change]}" "${L[clear]}"
    case "$_DV_ACT" in
      "${L[clear]}") DOMAIN_VERIFICATION_TOKENS="" ;;
      "${L[change]}") prompt "${L[domain_verification]}" DOMAIN_VERIFICATION_TOKENS ;;
      *) DOMAIN_VERIFICATION_TOKENS="$PREV_DV_TOKENS" ;;
    esac
  else
    echo ""
    prompt "${L[domain_verification]}" DOMAIN_VERIFICATION_TOKENS
  fi
fi
# Validate, normalize, then build the verification JSON body for the Lambda.
DOMAIN_VERIFICATION=""
if [ -n "${DOMAIN_VERIFICATION_TOKENS:-}" ]; then
  # Accept letters/digits/_/-/commas and any whitespace as separators on input...
  if [[ ! "$DOMAIN_VERIFICATION_TOKENS" =~ ^[A-Za-z0-9_,[:space:]-]+$ ]]; then
    err "Invalid verification token(s): only letters, digits, '_', '-', commas and spaces allowed"
    exit 1
  fi
  # ...then collapse to a canonical, space-free comma-joined form. Persisting THIS
  # (not the raw input) is what keeps the bare config write `source`-safe even if
  # the user typed "a, b" or pasted a newline-separated list. Reject separator-only
  # input (e.g. ",,") which would otherwise yield a served-but-empty {"tokens":[]}.
  DOMAIN_VERIFICATION_TOKENS=$(DV_TOKENS="$DOMAIN_VERIFICATION_TOKENS" python3 -c "
import os, re
toks = [t for t in re.split(r'[,\s]+', os.environ['DV_TOKENS'].strip()) if t]
print(','.join(toks))
")
  if [ -z "$DOMAIN_VERIFICATION_TOKENS" ]; then
    err "No valid verification token found (input was only separators)"
    exit 1
  fi
  DOMAIN_VERIFICATION=$(DV_TOKENS="$DOMAIN_VERIFICATION_TOKENS" python3 -c "
import json, os
toks = os.environ['DV_TOKENS'].split(',')
print(json.dumps({'tokens': toks}, separators=(',', ':')))
")
  _DV_COUNT=$(printf '%s' "$DOMAIN_VERIFICATION" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['tokens']))")
  info "AWS Security Agent domain verification: ${_DV_COUNT} token(s) configured"
fi

# WAF (default: off). Honor SKIP_WAF env override; on non-interactive default off.
if [ -n "${SKIP_WAF+x}" ]; then
  # Explicit env override
  if [ "${SKIP_WAF}" = "0" ]; then ENABLE_WAF=1; else ENABLE_WAF=0; fi
elif [ ! -t 0 ]; then
  ENABLE_WAF=0
else
  PREV_WAF=""
  if [ -f "$DEPLOY_CONFIG" ]; then
    PREV_WAF=$(grep '^SKIP_WAF=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  if [ "$PREV_WAF" = "0" ]; then _WAF_DEF=1; else _WAF_DEF=2; fi
  echo ""
  echo "  ${L[ask_waf]}"
  PICK_DEFAULT=$_WAF_DEF
  pick _WAF_PICK "${L[enable]}" "${L[disable]}"
  if [ "$_WAF_PICK" = "${L[enable]}" ]; then ENABLE_WAF=1; else ENABLE_WAF=0; fi
fi
if [ "$ENABLE_WAF" = "1" ]; then info "${L[waf_enabled]}"; else info "${L[waf_disabled]}"; fi
SKIP_WAF=$([ "$ENABLE_WAF" = "1" ] && echo 0 || echo 1)
export SKIP_WAF

# Log retention. Honor LOG_RETENTION_DAYS env override; on non-interactive
# stdin default to 90 without prompting.
if [ -z "${LOG_RETENTION_DAYS+x}" ]; then
  PREV_LOG_RET=""
  if [ -f "$DEPLOY_CONFIG" ]; then
    PREV_LOG_RET=$(grep '^LOG_RETENTION_DAYS=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  if [ ! -t 0 ]; then
    LOG_RETENTION_DAYS="${PREV_LOG_RET:-90}"
  elif [ -n "$PREV_LOG_RET" ]; then
    echo ""
    info "$(t log_retention_set "$PREV_LOG_RET")"
    if confirm "${L[log_retention_keep]}"; then
      LOG_RETENTION_DAYS="$PREV_LOG_RET"
    else
      echo ""
      echo "  ${L[ask_log_retention]}"
      echo ""
      PICK_DEFAULT=2
      pick _LOG_PICK "${L[log_30]}" "${L[log_90]}" "${L[log_180]}" "${L[log_365]}" "${L[log_never]}"
      case "$_LOG_PICK" in
        "${L[log_30]}")   LOG_RETENTION_DAYS="30" ;;
        "${L[log_180]}")  LOG_RETENTION_DAYS="180" ;;
        "${L[log_365]}")  LOG_RETENTION_DAYS="365" ;;
        "${L[log_never]}") LOG_RETENTION_DAYS="" ;;
        *)                LOG_RETENTION_DAYS="90" ;;
      esac
    fi
  else
    echo ""
    echo "  ${L[ask_log_retention]}"
    echo ""
    PICK_DEFAULT=2
    pick _LOG_PICK "${L[log_30]}" "${L[log_90]}" "${L[log_180]}" "${L[log_365]}" "${L[log_never]}"
    case "$_LOG_PICK" in
      30*)    LOG_RETENTION_DAYS="30" ;;
      180*)   LOG_RETENTION_DAYS="180" ;;
      365*)   LOG_RETENTION_DAYS="365" ;;
      never*) LOG_RETENTION_DAYS="" ;;
      *)      LOG_RETENTION_DAYS="90" ;;
    esac
  fi
fi
if [ -n "$LOG_RETENTION_DAYS" ]; then
  info "$(t log_retention_set "$LOG_RETENTION_DAYS")"
else
  info "${L[log_retention_forever]}"
fi
export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-}"

# AgentCore Runtime idle session timeout. Honors AGENTCORE_IDLE_TIMEOUT env;
# default 600s (10 min) — covers typical conversation bursts while saving idle
# vCPU-seconds vs the AWS default of 900s.
if [ -z "${AGENTCORE_IDLE_TIMEOUT+x}" ]; then
  PREV_IDLE=""
  if [ -f "$DEPLOY_CONFIG" ]; then
    PREV_IDLE=$(grep '^AGENTCORE_IDLE_TIMEOUT=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  if [ ! -t 0 ]; then
    AGENTCORE_IDLE_TIMEOUT="${PREV_IDLE:-600}"
  elif [ -n "$PREV_IDLE" ]; then
    echo ""
    info "$(t idle_timeout_set "$PREV_IDLE")"
    if confirm "${L[idle_timeout_keep]}"; then
      AGENTCORE_IDLE_TIMEOUT="$PREV_IDLE"
    else
      echo ""
      echo "  ${L[ask_idle_timeout]}"
      echo ""
      PICK_DEFAULT=2
      pick _IDLE_PICK "${L[idle_5min]}" "${L[idle_10min]}" "${L[idle_15min]}" "${L[idle_30min]}"
      case "$_IDLE_PICK" in
        "${L[idle_5min]}")  AGENTCORE_IDLE_TIMEOUT="300" ;;
        "${L[idle_15min]}") AGENTCORE_IDLE_TIMEOUT="900" ;;
        "${L[idle_30min]}") AGENTCORE_IDLE_TIMEOUT="1800" ;;
        *)                  AGENTCORE_IDLE_TIMEOUT="600" ;;
      esac
    fi
  else
    echo ""
    echo "  ${L[ask_idle_timeout]}"
    echo ""
    PICK_DEFAULT=2
    pick _IDLE_PICK "${L[idle_5min]}" "${L[idle_10min]}" "${L[idle_15min]}" "${L[idle_30min]}"
    case "$_IDLE_PICK" in
      "${L[idle_5min]}")  AGENTCORE_IDLE_TIMEOUT="300" ;;
      "${L[idle_15min]}") AGENTCORE_IDLE_TIMEOUT="900" ;;
      "${L[idle_30min]}") AGENTCORE_IDLE_TIMEOUT="1800" ;;
      *)                  AGENTCORE_IDLE_TIMEOUT="600" ;;
    esac
  fi
fi
# Defensive: guard against malformed env override (empty / non-integer / zero)
[[ "$AGENTCORE_IDLE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || AGENTCORE_IDLE_TIMEOUT="600"
info "$(t idle_timeout_set "$AGENTCORE_IDLE_TIMEOUT")"
export AGENTCORE_IDLE_TIMEOUT

# Alarm thresholds — preset picker + optional custom editor
ALARM_THRESHOLDS_FILE="${PROJECT_DIR}/config/alarm-thresholds.json"
ALARM_PRESETS_FILE="${PROJECT_DIR}/config/alarm-presets.json"
ALARM_OVERRIDES_FILE="${LOCAL_DIR}/alarm-thresholds.json"
if [ -t 0 ]; then
  echo ""
  echo "  ${L[ask_alarm_thresholds]}"
  _SKIP_ALARM_CONFIG=""
  if [ -f "$ALARM_OVERRIDES_FILE" ]; then
    if confirm "${L[alarm_thresholds_keep]}"; then
      _SKIP_ALARM_CONFIG=1
      info "${L[alarm_thresholds_kept]}"
    fi
  fi
  if [ -z "$_SKIP_ALARM_CONFIG" ]; then
    echo ""
    pick _ALARM_PRESET "${L[alarm_preset_standard]}" "${L[alarm_preset_relaxed]}" "${L[alarm_preset_strict]}" "${L[alarm_preset_custom]}"
  if [ "$_ALARM_PRESET" = "${L[alarm_preset_custom]}" ]; then
    echo ""
    # Build pick labels from alarm names + current thresholds
    mapfile -t _ALARM_LABELS < <(python3 -c "
import json, os
defaults = json.load(open('${ALARM_THRESHOLDS_FILE}'))
overrides_f = '${ALARM_OVERRIDES_FILE}'
overrides = json.load(open(overrides_f)) if os.path.exists(overrides_f) else {}
i18n = json.load(open('${PROJECT_DIR}/config/i18n.json'))
lang = '${LARK_LANG}'
names = i18n.get('alarmNames', {}).get(lang, i18n.get('alarmNames', {}).get('en', {}))
for k, v in defaults.items():
    t = overrides.get(k, v['threshold'])
    unit = v.get('unit', '') if lang == 'zh' else v.get('unit_en', v.get('unit', ''))
    label = names.get(k, k)
    print(f'{label}  [{t} {unit}]')
")
    _DONE_LABEL="${L[alarm_done]}"
    while true; do
      pick _ALARM_CHOICE "${_ALARM_LABELS[@]}" "$_DONE_LABEL"
      [ "$_ALARM_CHOICE" = "$_DONE_LABEL" ] && break
      # Get alarm key by index
      _ALARM_IDX=0
      for _i in "${!_ALARM_LABELS[@]}"; do
        if [ "${_ALARM_LABELS[$_i]}" = "$_ALARM_CHOICE" ]; then _ALARM_IDX=$_i; break; fi
      done
      # Show description and ask for new value
      _ALARM_INFO=$(python3 -c "
import json, os
defaults = json.load(open('${ALARM_THRESHOLDS_FILE}'))
overrides_f = '${ALARM_OVERRIDES_FILE}'
overrides = json.load(open(overrides_f)) if os.path.exists(overrides_f) else {}
i18n = json.load(open('${PROJECT_DIR}/config/i18n.json'))
lang = '${LARK_LANG}'
keys = list(defaults.keys())
k = keys[${_ALARM_IDX}]
v = defaults[k]
t = overrides.get(k, v['threshold'])
descs = {x.replace('alarm_desc_', ''): y for x, y in i18n.get('shell', {}).get(lang, i18n.get('shell', {}).get('en', {})).items() if x.startswith('alarm_desc_')}
desc = descs.get(k, '')
print(f'{desc}')
print(f'{v.get(\"range\", \"\")} {v.get(\"unit\", \"\")}')
print(f'{t}')
print(f'{k}')
")
      _DESC=$(echo "$_ALARM_INFO" | sed -n '1p')
      _RANGE=$(echo "$_ALARM_INFO" | sed -n '2p')
      _CURRENT=$(echo "$_ALARM_INFO" | sed -n '3p')
      _KEY=$(echo "$_ALARM_INFO" | sed -n '4p')
      echo ""
      info "$_DESC"
      info "  ($_RANGE)"
      ask "$_ALARM_CHOICE → " _NEW_VAL
      if [ -n "$_NEW_VAL" ] && [ "$_NEW_VAL" != "$_CURRENT" ]; then
        _OVERRIDES_F="$ALARM_OVERRIDES_FILE" _AKEY="$_KEY" _AVAL="$_NEW_VAL" python3 -c "
import json, os
overrides_f = os.environ['_OVERRIDES_F']
key = os.environ['_AKEY']
val_str = os.environ['_AVAL']
overrides = json.load(open(overrides_f)) if os.path.exists(overrides_f) else {}
try:
    overrides[key] = int(val_str) if '.' not in val_str else float(val_str)
    os.makedirs(os.path.dirname(overrides_f), exist_ok=True)
    json.dump(overrides, open(overrides_f, 'w'), indent=2)
    os.chmod(overrides_f, 0o600)
except ValueError:
    pass
"
        # Update the label for next loop iteration
        _ALARM_LABELS[$_ALARM_IDX]=$(python3 -c "
import json, os
defaults = json.load(open('${ALARM_THRESHOLDS_FILE}'))
overrides_f = '${ALARM_OVERRIDES_FILE}'
overrides = json.load(open(overrides_f)) if os.path.exists(overrides_f) else {}
i18n = json.load(open('${PROJECT_DIR}/config/i18n.json'))
lang = '${LARK_LANG}'
names = i18n.get('alarmNames', {}).get(lang, i18n.get('alarmNames', {}).get('en', {}))
keys = list(defaults.keys())
k = keys[${_ALARM_IDX}]
v = defaults[k]
t = overrides.get(k, v['threshold'])
unit = v.get('unit', '') if lang == 'zh' else v.get('unit_en', v.get('unit', ''))
print(f'{names.get(k, k)}  [{t} {unit}]')
")
      fi
      echo ""
    done
    info "${L[alarm_thresholds_custom]}"
  else
    # Apply preset
    _PRESET_NAME=""
    if [ "$_ALARM_PRESET" = "${L[alarm_preset_relaxed]}" ]; then _PRESET_NAME="relaxed"
    elif [ "$_ALARM_PRESET" = "${L[alarm_preset_strict]}" ]; then _PRESET_NAME="strict"
    else _PRESET_NAME="standard"
    fi
    python3 -c "
import json, os
presets = json.load(open('${ALARM_PRESETS_FILE}'))
preset = presets['${_PRESET_NAME}']
overrides_f = '${ALARM_OVERRIDES_FILE}'
os.makedirs(os.path.dirname(overrides_f), exist_ok=True)
json.dump(preset, open(overrides_f, 'w'), indent=2)
os.chmod(overrides_f, 0o600)
"
    info "$(t alarm_preset_applied "$_ALARM_PRESET")"
  fi
  fi
fi

# Alarm webhook. Persisted in SSM so re-deploys can read the previous value.
# Honor ALARM_WEBHOOK_URL env override; on non-interactive stdin, skip prompt.
# WEBHOOK_SSM_NAME is per-slug (exported by slug.sh) — a single global param
# would silently re-point app A's webhook Lambda at app B's channel on the
# non-interactive --yes redeploy path (major fix).
if [ -z "${ALARM_WEBHOOK_URL+x}" ]; then
  EXISTING_WEBHOOK=$(aws ssm get-parameter --name "$WEBHOOK_SSM_NAME" --region "$REGION" \
    --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  if [ ! -t 0 ]; then
    ALARM_WEBHOOK_URL="${EXISTING_WEBHOOK}"
  elif [ -n "$EXISTING_WEBHOOK" ]; then
    echo ""
    info "$(t webhook_existing "${EXISTING_WEBHOOK:0:60}...")"
    pick _WEBHOOK_ACT "${L[keep]}" "${L[change]}" "${L[clear]}"
    case "$_WEBHOOK_ACT" in
      "${L[clear]}") ALARM_WEBHOOK_URL="" ;;
      "${L[change]}")
        echo ""
        info "${L[webhook_hint]}"
        ask "${L[ask_webhook]}" ALARM_WEBHOOK_URL
        ;;
      *) ALARM_WEBHOOK_URL="$EXISTING_WEBHOOK" ;;
    esac
  else
    echo ""
    info "${L[webhook_hint]}"
    ask "${L[ask_webhook]}" ALARM_WEBHOOK_URL
  fi
fi
if [ -n "$ALARM_WEBHOOK_URL" ]; then
  if aws ssm get-parameter --name "$WEBHOOK_SSM_NAME" --region "$REGION" &>/dev/null; then
    aws ssm put-parameter --name "$WEBHOOK_SSM_NAME" --value "$ALARM_WEBHOOK_URL" \
      --type String --region "$REGION" --overwrite >/dev/null 2>&1
  else
    aws ssm put-parameter --name "$WEBHOOK_SSM_NAME" --value "$ALARM_WEBHOOK_URL" \
      --type String --region "$REGION" \
      --tags "Key=project,Value=lark-mcp-on-agentcore" >/dev/null 2>&1
  fi
  info "${L[webhook_set]}"
else
  # Clear persisted value if user explicitly cleared it
  if [ "${_WEBHOOK_ACT:-}" = "${L[clear]}" ]; then
    aws ssm delete-parameter --name "$WEBHOOK_SSM_NAME" --region "$REGION" >/dev/null 2>&1 || true
    info "${L[webhook_cleared]}"
  else
    info "${L[webhook_skip]}"
  fi
fi
export ALARM_WEBHOOK_URL="${ALARM_WEBHOOK_URL:-}"

# Webhook security (keyword + signature secret)
if [ -n "$ALARM_WEBHOOK_URL" ] && [ -t 0 ]; then
  if [ -z "${ALARM_WEBHOOK_SECRET+x}" ]; then
    ALARM_WEBHOOK_SECRET=$(grep '^ALARM_WEBHOOK_SECRET=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  if [ -z "${ALARM_WEBHOOK_KEYWORD+x}" ]; then
    ALARM_WEBHOOK_KEYWORD=$(grep '^ALARM_WEBHOOK_KEYWORD=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  if [ -z "$ALARM_WEBHOOK_SECRET" ] && [ -z "$ALARM_WEBHOOK_KEYWORD" ] && [ "${_WEBHOOK_ACT:-}" != "${L[keep]}" ]; then
    echo ""
    ask "${L[ask_webhook_secret]}" ALARM_WEBHOOK_SECRET
    ask "${L[ask_webhook_keyword]}" ALARM_WEBHOOK_KEYWORD
  fi
fi
export ALARM_WEBHOOK_SECRET="${ALARM_WEBHOOK_SECRET:-}"
export ALARM_WEBHOOK_KEYWORD="${ALARM_WEBHOOK_KEYWORD:-}"

# CDK Bootstrap (deploy region + us-east-1 for the CloudFront-scope WAF)
ensure_bootstrap() {
  local target_region="$1"
  local check
  check=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region "$target_region" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$check" = "NOT_FOUND" ]; then
    info "$(t not_bootstrapped "$target_region")"
    if confirm "${L[run_bootstrap]}"; then
      ( cd "${PROJECT_DIR}/infra" && npm install --silent 2>/dev/null && \
        AWS_REGION="$target_region" npx cdk bootstrap "aws://${ACCOUNT_ID}/${target_region}" )
    else
      err "Bootstrap required: npx cdk bootstrap aws://${ACCOUNT_ID}/${target_region}"
      exit 1
    fi
  else
    info "CDK Bootstrap (${target_region}): ✓"
  fi
}
ensure_bootstrap "$REGION"
# Bootstrap us-east-1 only when WAF is being deployed (CloudFront-scope WAF
# requires us-east-1).
if [ "${SKIP_WAF:-0}" != "1" ] && [ "$REGION" != "us-east-1" ]; then
  ensure_bootstrap "us-east-1"
fi

# 确认
step confirm_deploy
info "App ID:       ${APP_ID}"
info "Region:       ${REGION}"
info "Account:      ${ACCOUNT_ID}"
echo ""
if ! confirm "${L[start_deploy]}"; then
  echo "  ${L[cancelled]}"
  exit 0
fi

DEPLOY_STARTED=true

# 清理残留资源
info "${L[clean_residuals]}"
for STACK_NAME in "$OAUTH_STACK" "$RUNTIME_STACK"; do
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
    warn "Stack ${STACK_NAME} status: ${STACK_STATUS}, deleting..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
  fi
done

# WAF lives in us-east-1 regardless of deploy region. It is SHARED across all
# apps (WAF_STACK is never slug-suffixed).
WAF_STATUS=$(aws cloudformation describe-stacks --stack-name "$WAF_STACK" --region "us-east-1" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
# count_oauth_consumers: how many LarkMcpOnAgentCoreOAuth* stacks still exist
# (across all slugs). The shared WAF's cross-region export is read by each OAuth
# stack, so the WAF must NOT be destroyed while any consumer remains.
count_oauth_consumers() {
  aws cloudformation list-stacks --region "$REGION" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE \
    --query "StackSummaries[?starts_with(StackName, 'LarkMcpOnAgentCoreOAuth')].StackName" \
    --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true
}
# H4: if the user opted out of WAF this run but a WAF stack from a prior run
# still exists, destroy it ONLY when no OAuth consumer remains — otherwise
# destroying the cross-region export producer throws and/or breaks other apps.
if [ "${SKIP_WAF:-0}" = "1" ] && [ "$WAF_STATUS" != "NOT_FOUND" ] && \
   [ "$WAF_STATUS" != "DELETE_IN_PROGRESS" ] && \
   [ "$WAF_STATUS" != "DELETE_COMPLETE" ]; then
  if [ "$(count_oauth_consumers)" -gt 0 ]; then
    warn "WAF disabled this run but ${WAF_STACK} is shared and still has OAuth consumers; leaving it in place."
  else
    warn "WAF disabled this run but Stack ${WAF_STACK} still exists (${WAF_STATUS}) with no consumers. Destroying..."
    ( cd "${PROJECT_DIR}/infra" && AWS_REGION="us-east-1" SKIP_WAF=0 npx cdk destroy "$WAF_STACK" --force ) || \
      warn "WAF stack destroy failed; manual cleanup may be required."
    WAF_STATUS="NOT_FOUND"
  fi
fi
# A failed/rolled-back WAF stack normally needs deleting before re-create — but
# the WAF is SHARED, so a DELETE_FAILED that occurs AFTER it was consumed must
# not be force-deleted while another app's OAuth stack still imports its
# cross-region export. Guard with the same consumer count as the SKIP_WAF branch.
if [ "$WAF_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$WAF_STATUS" = "DELETE_FAILED" ]; then
  if [ "$(count_oauth_consumers)" -gt 0 ]; then
    warn "Shared WAF (${WAF_STACK}) is ${WAF_STATUS} but still has OAuth consumers; NOT deleting. Manual intervention may be needed."
  else
    warn "Stack ${WAF_STACK} status: ${WAF_STATUS}, deleting..."
    aws cloudformation delete-stack --stack-name "$WAF_STACK" --region "us-east-1" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete --stack-name "$WAF_STACK" --region "us-east-1" 2>/dev/null || true
  fi
fi

SECRET_NAME="$FEISHU_SECRET"
  SECRET_STATUS=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" \
    --query 'DeletedDate' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$SECRET_STATUS" != "NOT_FOUND" ] && [ "$SECRET_STATUS" != "None" ]; then
    info "Cleaning pending-delete secret: ${SECRET_NAME}"
    aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
      --force-delete-without-recovery 2>/dev/null || true
  elif [ "$SECRET_STATUS" = "None" ]; then
    OWNING_STACK=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region "$REGION" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$OWNING_STACK" = "NOT_FOUND" ]; then
      warn "Orphaned secret ${SECRET_NAME}, cleaning..."
      aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
        --force-delete-without-recovery 2>/dev/null || true
    fi
  fi

SSM_EXISTS=$(aws ssm get-parameter --name "$STATE_PARAM" --region "$REGION" \
  --query 'Parameter.Name' --output text 2>/dev/null || echo "NOT_FOUND")
OAUTH_STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$SSM_EXISTS" != "NOT_FOUND" ] && [ "$OAUTH_STACK_EXISTS" = "NOT_FOUND" ]; then
  info "Cleaning orphaned SSM: ${STATE_PARAM}"
  aws ssm delete-parameter --name "$STATE_PARAM" --region "$REGION" 2>/dev/null || true
fi

info "Clean up done ✓"

step step_1
echo ""
info "${L[creating_secrets]}"
SECRET_FILE=$(mktemp); chmod 600 "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE"' EXIT
APP_ID="$APP_ID" APP_SECRET="$APP_SECRET" python3 -c \
  'import json,os; print(json.dumps({"appId":os.environ["APP_ID"],"appSecret":os.environ["APP_SECRET"]}))' > "$SECRET_FILE"
if aws secretsmanager describe-secret --secret-id "$FEISHU_SECRET" --region "$REGION" &>/dev/null; then
  aws secretsmanager put-secret-value --secret-id "$FEISHU_SECRET" \
    --secret-string "file://$SECRET_FILE" --region "$REGION" >/dev/null 2>&1
  info "Secret updated ✓"
else
  aws secretsmanager create-secret --name "$FEISHU_SECRET" \
    --secret-string "file://$SECRET_FILE" --region "$REGION" \
    --tags Key=project,Value=lark-mcp-on-agentcore Key=app,Value="${SLUG:-default}" >/dev/null 2>&1
  info "Secret created ✓"
fi
rm -f "$SECRET_FILE"
trap - EXIT

put_secure_param() {
  local name="$1"
  local value="$2"
  local f
  f=$(mktemp); chmod 600 "$f"
  printf '%s' "$value" > "$f"
  aws ssm put-parameter --name "$name" --value "file://$f" \
    --type SecureString --region "$REGION" \
    --tags "Key=project,Value=lark-mcp-on-agentcore" >/dev/null 2>&1
  rm -f "$f"
}

# Create-if-absent (per slug): the signing root must NOT rotate on re-deploy or
# all live MCP tokens for this app would be invalidated. Per-slug param name
# (Killer Fix #2) keeps each app's signing domain disjoint.
if ! aws ssm get-parameter --name "$STATE_PARAM" --region "$REGION" &>/dev/null; then
  STATE_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  put_secure_param "$STATE_PARAM" "$STATE_SECRET_VAL"
  info "State secret created ✓"
else
  STATE_SECRET_VAL=$(aws ssm get-parameter --name "$STATE_PARAM" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "State secret exists ✓"
fi

if ! aws ssm get-parameter --name "$OAUTH_SECRET_PARAM" --region "$REGION" &>/dev/null; then
  OAUTH_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  put_secure_param "$OAUTH_SECRET_PARAM" "$OAUTH_SECRET_VAL"
  info "OAuth Client Secret created ✓"
else
  OAUTH_SECRET_VAL=$(aws ssm get-parameter --name "$OAUTH_SECRET_PARAM" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "OAuth Client Secret exists ✓"
fi

info "${L[building]}"
cd "${PROJECT_DIR}"
npm install --silent 2>/dev/null
( cd "${PROJECT_DIR}/docker" && npm install --omit=dev --silent --no-audit --no-fund 2>/dev/null )
cd "${PROJECT_DIR}/infra"
npm install --silent 2>/dev/null
export CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-}"
export EXTRA_ALLOWED_DOMAINS="${EXTRA_ALLOWED_DOMAINS:-}"
export DOMAIN_VERIFICATION="${DOMAIN_VERIFICATION:-}"
CDK_STACKS=("$RUNTIME_STACK" "$OAUTH_STACK")
# Shared-WAF deploy-set exclusion (BLOCKER fix): the WAF stack is shared across
# all apps and is NOT slug-suffixed. Re-synthing it on a 2nd+ app deploy would
# drop the first app's still-strong-ref'd cross-region reader export and make the
# CDK cross-region SSM writer THROW `Exports cannot be updated: ... in use by
# stack(s)`. So include the WAF in CDK_STACKS ONLY on its first-ever creation
# (WAF_STATUS == NOT_FOUND). Once it exists, every OAuth stack just imports it by
# name; the producer is never re-synthed.
if [ "${SKIP_WAF:-0}" != "1" ] && [ "$WAF_STATUS" = "NOT_FOUND" ]; then
  CDK_STACKS=("$RUNTIME_STACK" "$WAF_STACK" "$OAUTH_STACK")
fi
if ! AWS_REGION="$REGION" npx cdk deploy "${CDK_STACKS[@]}" -c "slug=${SLUG}" --require-approval never 2>&1 | tee /tmp/cdk-deploy.log; then
  echo ""
  err "${L[cdk_failed]}"
  tail -20 /tmp/cdk-deploy.log
  exit 1
fi

# 提取输出
IMAGE_URI=$(aws cloudformation describe-stacks --stack-name "$RUNTIME_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ImageUri`].OutputValue' --output text 2>/dev/null || echo "")
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$RUNTIME_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RuntimeRoleArn`].OutputValue' --output text 2>/dev/null || echo "")
OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
REDIRECT_URL=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FeishuRedirectUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -z "$IMAGE_URI" ] || [ -z "$ROLE_ARN" ]; then
  err "${L[cdk_check]}"
  exit 1
fi
info "Image: ${IMAGE_URI}"
info "OAuth: ${OAUTH_ENDPOINT}"

# 设置 OAuth Lambda
OAUTH_FN=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthFunctionName`].OutputValue' --output text 2>/dev/null || echo "")
STATE_SECRET_VAL=$(aws ssm get-parameter --name "$STATE_PARAM" --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')
OAUTH_SECRET_VAL=$(aws ssm get-parameter --name "$OAUTH_SECRET_PARAM" --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')

# Read OAuth scopes from config file
SCOPES_FILE="${PROJECT_DIR}/config/oauth-scopes.json"
if [ -f "$SCOPES_FILE" ]; then
  FEISHU_SCOPES=$(python3 -c "
import json, re, sys
scopes = json.load(open('${SCOPES_FILE}'))
valid = [s for s in scopes if re.match(r'^[a-z0-9_:.\-]+$', s)]
if len(valid) != len(scopes):
    print(f'WARNING: {len(scopes)-len(valid)} invalid scopes skipped', file=sys.stderr)
print(' '.join(valid))
")
  info "OAuth scopes: $(echo $FEISHU_SCOPES | wc -w | tr -d ' ') from config/oauth-scopes.json ✓"
else
  FEISHU_SCOPES=""
  warn "config/oauth-scopes.json not found, OAuth will request basic permissions only"
fi

if [ -n "$OAUTH_FN" ] && [ -n "$OAUTH_ENDPOINT" ]; then
  # Use file:// to avoid leaking secrets in `ps auxww` argv during the AWS CLI invocation.
  ENV_FILE=$(mktemp); chmod 600 "$ENV_FILE"
  trap 'rm -f "$ENV_FILE"' RETURN  2>/dev/null || true
  CALLBACK_URL="${OAUTH_ENDPOINT}/callback" \
    OAUTH_SECRET_VAL="$OAUTH_SECRET_VAL" \
    FEISHU_SCOPES="$FEISHU_SCOPES" \
    CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-}" \
    EXTRA_ALLOWED_DOMAINS="${EXTRA_ALLOWED_DOMAINS:-}" \
    DOMAIN_VERIFICATION="${DOMAIN_VERIFICATION:-}" \
    SECRET_USERS_PREFIX="$SECRET_USERS_PREFIX" \
    FEISHU_SECRET="$FEISHU_SECRET" \
    STATE_PARAM="$STATE_PARAM" \
    OAUTH_CLIENT_ID="$OAUTH_CLIENT_ID" \
    CODE_TABLE="$CODE_TABLE" \
    OPENID_TABLE="$OPENID_TABLE" \
    python3 -c '
import json, os
# update-function-configuration REPLACES the whole env, so every per-slug value
# must be threaded through here (a missed one regresses isolation even if CDK is
# correct). All names come from the slug resolver via os.environ.
vars = {
  "CALLBACK_URL": os.environ["CALLBACK_URL"],
  "SECRET_PREFIX": os.environ["SECRET_USERS_PREFIX"],
  "APP_SECRET_ID": os.environ["FEISHU_SECRET"],
  "STATE_SECRET_PARAM": os.environ["STATE_PARAM"],
  "OAUTH_CLIENT_ID": os.environ["OAUTH_CLIENT_ID"],
  "OAUTH_CLIENT_SECRET": os.environ["OAUTH_SECRET_VAL"],
  "FEISHU_SCOPES": os.environ.get("FEISHU_SCOPES", ""),
  "CODE_TABLE": os.environ["CODE_TABLE"],
  "OPENID_TABLE": os.environ["OPENID_TABLE"],
}
# ALLOWED_DOMAINS = the custom domain (if any) + any extra OAuth redirect hosts
# (for non-loopback clients), comma-joined. Emitted unconditionally so the value
# is explicit. See docs/connect-mcp-clients.
_allowed = []
if os.environ.get("CUSTOM_DOMAIN"):
  _allowed.append(os.environ["CUSTOM_DOMAIN"])
for _d in os.environ.get("EXTRA_ALLOWED_DOMAINS", "").replace(" ", "").split(","):
  if _d and _d not in _allowed:
    _allowed.append(_d)
vars["ALLOWED_DOMAINS"] = ",".join(_allowed)
# This update-function-configuration REPLACES the whole env set, so every var the
# Lambda needs must be re-listed here — including DOMAIN_VERIFICATION, else the
# value CDK set would be wiped. Empty string keeps the verification route inert.
if os.environ.get("DOMAIN_VERIFICATION"):
  vars["DOMAIN_VERIFICATION"] = os.environ["DOMAIN_VERIFICATION"]
print(json.dumps({"Variables": vars}))
' > "$ENV_FILE"
  aws lambda update-function-configuration \
    --function-name "$OAUTH_FN" \
    --environment "file://$ENV_FILE" \
    --region "$REGION" >/dev/null 2>&1
  rm -f "$ENV_FILE"
  info "OAuth Lambda configured ✓"
fi

# Migrate openid-map from Secrets Manager to DynamoDB (one-time, idempotent).
# Safe ordering: CDK already created the DDB table, and the Lambda env update above
# set OPENID_TABLE — so new OAuth callbacks already write to DDB. This migration
# only backfills pre-existing SM entries. SM entries use the default 30-day recovery
# window (no ForceDeleteWithoutRecovery) to allow rollback if needed.
OPENID_SM_PREFIX="lark-mcp-on-agentcore/openid-map"
OPENID_DDB_TABLE="$OPENID_TABLE"
# This is a one-time backfill of legacy Secrets-Manager-based openid mappings
# that only the ORIGINAL (default) deployment can ever have. A fresh per-slug app
# has no such legacy entries, so gate the whole migration on the default sentinel
# (empty SLUG). NOTE: the sentinel is the empty string — a literal `= default`
# test would never fire and would skip the backfill on the deploy that needs it.
OPENID_COUNT=0
if [ -z "$SLUG" ]; then
  # length(@) is applied per-page by the CLI paginator (prints "10\n6" past one
  # page), which would break the -gt test and over/under-report the migration
  # count; count names client-side. (--no-paginate would undercount to page 1.)
  OPENID_COUNT=$(aws secretsmanager list-secrets --region "$REGION" \
    --filters "Key=name,Values=${OPENID_SM_PREFIX}" \
    --query 'SecretList[].Name' --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)
fi
if [ "${OPENID_COUNT:-0}" -gt 0 ]; then
  info "Migrating ${OPENID_COUNT} openid-map entries from Secrets Manager to DynamoDB..."
  python3 -c "
import boto3, json
region = '$REGION'
sm = boto3.client('secretsmanager', region_name=region)
ddb = boto3.resource('dynamodb', region_name=region).Table('$OPENID_DDB_TABLE')
paginator = sm.get_paginator('list_secrets')
migrated = 0
for page in paginator.paginate(Filters=[{'Key': 'name', 'Values': ['$OPENID_SM_PREFIX']}]):
    for s in page.get('SecretList', []):
        name = s['Name']
        open_id = name.replace('$OPENID_SM_PREFIX/', '')
        try:
            val = sm.get_secret_value(SecretId=name)
            user_id = json.loads(val['SecretString'])['userId']
            ddb.put_item(Item={'openId': open_id, 'userId': user_id})
            sm.delete_secret(SecretId=name)
            migrated += 1
        except Exception as e:
            print(f'  WARN: skip {name}: {e}')
print(f'  Migrated {migrated}/{$OPENID_COUNT} entries')
"
  info "OpenID mapping migration complete ✓"
fi

# AgentCore Runtime
step step_2
RUNTIME_ID=$(APP_ID="$APP_ID" REGION="$REGION" ROLE_ARN="$ROLE_ARN" \
  IMAGE_URI="$IMAGE_URI" OAUTH_ENDPOINT="$OAUTH_ENDPOINT" \
  AGENTCORE_IDLE_TIMEOUT="$AGENTCORE_IDLE_TIMEOUT" \
  RUNTIME_NAME="$RUNTIME_NAME" APP_SECRET_ID_VAL="$FEISHU_SECRET" APP_TAG="${SLUG:-default}" \
  python3 << 'PYEOF'
import os, boto3, sys
region = os.environ['REGION']
runtime_name = os.environ['RUNTIME_NAME']
c = boto3.client('bedrock-agentcore-control', region_name=region)
runtime_config = {
    'roleArn': os.environ['ROLE_ARN'],
    'agentRuntimeArtifact': {'containerConfiguration': {'containerUri': os.environ['IMAGE_URI']}},
    'networkConfiguration': {'networkMode': 'PUBLIC'},
    'protocolConfiguration': {'serverProtocol': 'MCP'},
    'lifecycleConfiguration': {'idleRuntimeSessionTimeout': int(os.environ['AGENTCORE_IDLE_TIMEOUT'])},
    'requestHeaderConfiguration': {'requestHeaderAllowlist': ['X-User-Access-Token', 'X-Runtime-User-Id', 'X-Incr-Auth-Token']},
    'environmentVariables': {
        'APP_ID': os.environ['APP_ID'],
        'APP_SECRET_ID': os.environ['APP_SECRET_ID_VAL'],
        'AWS_REGION': region,
        'LARKSUITE_CLI_BRAND': 'feishu',
        'AUTHORIZE_BASE': os.environ['OAUTH_ENDPOINT'],
    },
}
try:
    resp = c.create_agent_runtime(
        agentRuntimeName=runtime_name,
        description='Lark MCP Server (lark-cli)',
        tags={'project': 'lark-mcp-on-agentcore', 'app': os.environ['APP_TAG']},
        **runtime_config,
    )
    print(resp['agentRuntimeId'])
except Exception as e:
    if 'Conflict' in str(e):
        next_token = None
        while True:
            kwargs = {'nextToken': next_token} if next_token else {}
            runtimes = c.list_agent_runtimes(**kwargs)
            for r in runtimes.get('agentRuntimes', []):
                if r.get('agentRuntimeName') == runtime_name:
                    rid = r['agentRuntimeId']
                    # update_agent_runtime does not accept tags; tags persist from create
                    c.update_agent_runtime(agentRuntimeId=rid, **runtime_config)
                    print(rid)
                    sys.exit(0)
            next_token = runtimes.get('nextToken')
            if not next_token: break
    print(f'ERROR:{e}', file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [ -z "$RUNTIME_ID" ] || [[ "$RUNTIME_ID" == ERROR* ]]; then
  err "${L[runtime_failed]}"
  exit 1
fi
info "Runtime: ${RUNTIME_ID}"

info "${L[waiting_runtime]}"
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
for i in range(60):
    r = c.get_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
    s = r['status']
    if s == 'READY': print('  Ready ✓'); sys.exit(0)
    if s in ('FAILED','CREATE_FAILED'): print(f'  Failed: {r.get(\"failureReason\",\"?\")}', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  Timeout', file=sys.stderr); sys.exit(1)
"

# Runtime Endpoint
step step_3
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
# Get current runtime version (may be > 1 after updates)
rt = c.get_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
version = str(rt.get('agentRuntimeVersion', '1'))
try:
    c.create_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', name='ep', agentRuntimeVersion=version)
except Exception as e:
    if 'Conflict' in str(e):
        c.update_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep', agentRuntimeVersion=version)
    else:
        print(f'  Warning: {e}', file=sys.stderr)
for i in range(30):
    r = c.get_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep')
    if r['status'] == 'READY': print('  Endpoint ready ✓'); sys.exit(0)
    if r['status'] == 'FAILED': print('  Endpoint creation failed', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  Timeout', file=sys.stderr); sys.exit(1)
"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"

# 配置 Middleware
step step_4
MIDDLEWARE_FN=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`MiddlewareFunctionName`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$MIDDLEWARE_FN" ]; then
  aws lambda update-function-configuration \
    --function-name "$MIDDLEWARE_FN" \
    --environment "Variables={RUNTIME_ARN=${RUNTIME_ARN},SECRET_PREFIX=${SECRET_USERS_PREFIX},STATE_SECRET_PARAM=${STATE_PARAM},AUTHORIZE_BASE=${OAUTH_ENDPOINT},DEPLOY_REGION=${REGION}}" \
    --region $REGION >/dev/null 2>&1
  info "Middleware configured ✓"
else
  warn "Middleware Lambda not found. Check ${OAUTH_STACK} Stack."
fi

# MCP endpoint
MCP_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`McpEndpoint`].OutputValue' --output text 2>/dev/null || echo "N/A")
DASHBOARD_URL=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' --output text 2>/dev/null || echo "")

# 验证
step verify
info "${L[testing_oauth]}"
# Use the OAuth metadata endpoint as the healthcheck — /authorize requires either
# a full PKCE redirect_uri or a signed t= token, so a bare GET would (correctly) 400.
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/.well-known/oauth-authorization-server" 2>/dev/null || echo "000")
[ "$HTTP" = "200" ] && info "OAuth metadata: ✓" || warn "OAuth metadata: HTTP ${HTTP}"

info "${L[testing_runtime]}"
python3 -c "
import boto3, json, sys
c = boto3.client('bedrock-agentcore', region_name='${REGION}', config=boto3.session.Config(read_timeout=30))
try:
    resp = c.invoke_agent_runtime(agentRuntimeArn='${RUNTIME_ARN}', contentType='application/json', accept='application/json, text/event-stream',
        payload=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'verify','version':'1'}}}))
    body = resp['response'].read().decode()
    if 'serverInfo' in body: print('  Runtime MCP: ✓')
    else: print('  Runtime response format unexpected')
except Exception as e:
    print(f'  Runtime: cold start (retry in 30s)')
" 2>&1

DEPLOY_STARTED=false

# Save deploy config for next run. We persist the normalized token(s) — a
# space-free comma-joined string of [A-Za-z0-9_-] tokens, not the built JSON — so
# the bare write is always safe to `source` back (no spaces/quotes/metachars).
cat > "$DEPLOY_CONFIG" << CFGEOF
LARK_LANG=${LARK_LANG}
REGION=${REGION}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN:-}
EXTRA_ALLOWED_DOMAINS=${EXTRA_ALLOWED_DOMAINS:-}
DOMAIN_VERIFICATION_TOKENS=${DOMAIN_VERIFICATION_TOKENS:-}
SKIP_WAF=${SKIP_WAF}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-}
AGENTCORE_IDLE_TIMEOUT=${AGENTCORE_IDLE_TIMEOUT:-600}
ALARM_WEBHOOK_SECRET=${ALARM_WEBHOOK_SECRET:-}
ALARM_WEBHOOK_KEYWORD=${ALARM_WEBHOOK_KEYWORD:-}
CFGEOF
chmod 600 "$DEPLOY_CONFIG"

# Record/refresh this app in the registry (for `ops.sh list-apps` and
# `upgrade.sh --all`). Only named apps; the default app is implicit.
if [ -n "$SLUG" ]; then
  upsert_app "$SLUG" "$APP_ALIAS" "$REGION" "$MCP_ENDPOINT" "$RUNTIME_NAME"
fi

# OAuth Client 信息 (OAUTH_CLIENT_ID is exported per-slug by slug.sh)
OAUTH_CLIENT_SECRET_VAL="${OAUTH_SECRET_VAL}"

# 保存部署信息 (per-slug so apps don't overwrite each other's output)
if [ -n "$SLUG" ]; then
  DEPLOY_INFO="${APP_LOCAL_DIR}/deploy-output.md"
else
  DEPLOY_INFO="${LOCAL_DIR}/deploy-output.md"
fi
umask 077
cat > "$DEPLOY_INFO" << INFOEOF
# Lark MCP on AgentCore - Deployment Info

> Deployed: $(date '+%Y-%m-%d %H:%M:%S')
> Region: ${REGION}
> Account: ${ACCOUNT_ID}

## Connect (Kiro / Claude Code / Codex)

\`\`\`json
{ "mcpServers": { "feishu": { "type": "http", "url": "${MCP_ENDPOINT}" } } }
\`\`\`

Save → authorize in browser → done. Details: docs/connect-mcp-clients_en.md

## Amazon Quick Desktop (requires Client Secret)

Settings → Capabilities → Browse Connections → Connectors →
Create for your team → Model Context Protocol → No, create new

| Field | Value |
|-------|-------|
| Name | Feishu Remote MCP |
| MCP server endpoint | ${MCP_ENDPOINT} |
| Connection type | public |
| Client ID | ${OAUTH_CLIENT_ID} |
| Client Secret | ${OAUTH_CLIENT_SECRET_VAL} |
| Token URL | ${OAUTH_ENDPOINT}/token |
| Authorization URL | ${OAUTH_ENDPOINT}/authorize |

Save → Connect → Authorize in browser → Connected.

## Feishu App Settings (first deploy only)

Open: https://open.feishu.cn/app/${APP_ID}/safe

Add redirect URL: ${REDIRECT_URL}

## Operations

\`\`\`bash
./scripts/ops.sh list-users       # List authorized users
./scripts/ops.sh revoke <id>      # Revoke user authorization
./scripts/ops.sh status           # System overview

./scripts/teardown.sh   # Destroy AgentCore Runtime + all CDK stacks
\`\`\`

## Run Tests

\`\`\`bash
RUNTIME_ARN=${RUNTIME_ARN} OAUTH_ENDPOINT=${OAUTH_ENDPOINT} ./scripts/test-e2e.sh
\`\`\`
INFOEOF
chmod 600 "$DEPLOY_INFO"

# 完成
echo ""
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
printf "  ║         %-32s║\n" "${L[title_done]}"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ${L[deploy_info]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  MCP Endpoint:          ${MCP_ENDPOINT}"
echo "  OAuth Client ID:       ${OAUTH_CLIENT_ID}"
echo "  OAuth Client Secret:   ${OAUTH_CLIENT_SECRET_VAL}"
echo "  Token URL:             ${OAUTH_ENDPOINT}/token"
echo "  Authorization URL:     ${OAUTH_ENDPOINT}/authorize"
echo "  Redirect URL:          ${REDIRECT_URL}"
if [ -n "$DASHBOARD_URL" ]; then
echo "  Dashboard:             ${DASHBOARD_URL}"
fi
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ${L[clients_title]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "    ${L[clients_json]//<MCP Endpoint>/${MCP_ENDPOINT}}"
echo "    ${L[clients_cc]}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ${L[quick_title]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "    ${L[step2_nav]}"
echo "    ${L[step2_browser]}"
echo "    No, create new"
echo ""
echo "    ${L[conn_info]}"
echo "      Name:               Feishu Remote MCP"
echo "      MCP server endpoint: ${MCP_ENDPOINT}"
echo "      Connection type:    public"
echo ""
echo "    ${L[oauth_config]}"
echo "      Client ID:          ${OAUTH_CLIENT_ID}"
echo "      Client Secret:      ${OAUTH_CLIENT_SECRET_VAL}"
echo "      Token URL:          ${OAUTH_ENDPOINT}/token"
echo "      Authorization URL:  ${OAUTH_ENDPOINT}/authorize"
echo ""
echo "    ${L[save_connect]}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ${L[feishu_app_title]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "    ${L[step1_open]}"
echo "    https://open.feishu.cn/app/${APP_ID}/safe"
echo ""
echo "    ${L[step1_add]}"
echo "    ${REDIRECT_URL}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ${L[operations]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ${L[op_list]}"
echo "  ${L[op_revoke]}"
echo "  ${L[op_status]}"
echo "  ${L[op_destroy]}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${L[info_saved]} ${CYAN}${DEPLOY_INFO}${NC}"
echo ""
