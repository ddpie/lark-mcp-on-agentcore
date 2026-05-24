#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "" >&2
  echo "  bash 4+ required (current: ${BASH_VERSION})" >&2
  echo "" >&2
  if command -v brew &>/dev/null; then
    printf "  Install bash 4+ via Homebrew and continue? (Y/n) " >&2
    read -r _ans </dev/tty 2>/dev/null || _ans="y"
    if [[ ! "${_ans:-y}" =~ ^[nN] ]]; then
      brew install bash
      NEW_BASH="$(brew --prefix)/bin/bash"
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
DEPLOY_CONFIG="${LOCAL_DIR}/deploy-config"

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
  if [ ! -t 0 ] || [ ! -t 1 ]; then
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
prompt() { drain_stdin; read -rp "  $1" "$2" </dev/tty; }
ask() { drain_stdin; read -rp "  $1: " "$2" </dev/tty; }

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
  err "${L[docker_not_running]}"
  DEPS_OK=false
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
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
# Override with saved region from previous deploy if available
if [ -f "$DEPLOY_CONFIG" ]; then
  SAVED_REGION=$(grep '^REGION=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
  [ -n "$SAVED_REGION" ] && REGION="$SAVED_REGION"
fi
info "AWS Account: ${ACCOUNT_ID}"
info "Region: ${REGION}"

# 配置飞书应用
step configure_feishu

# Check if credentials already exist in Secrets Manager (from a prior deploy)
EXISTING_CREDS=""
EXISTING_APP_ID=""
if aws secretsmanager describe-secret --secret-id "lark-mcp-on-agentcore/feishu-app" --region "$REGION" &>/dev/null; then
  EXISTING_CREDS=$(aws secretsmanager get-secret-value --secret-id "lark-mcp-on-agentcore/feishu-app" --region "$REGION" \
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
      VERIFY_CODE=$(echo "$VERIFY_RESP" | grep -o '"code":[0-9]*' | head -1 | cut -d: -f2)
      if [ "${VERIFY_CODE:-}" = "0" ]; then
        info "${L[creds_valid]}"
        break
      else
        VERIFY_MSG=$(echo "$VERIFY_RESP" | grep -o '"msg":"[^"]*"' | head -1 | cut -d'"' -f4)
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
export SKIP_WAF=$([ "$ENABLE_WAF" = "1" ] && echo 0 || echo 1)

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
WEBHOOK_SSM_NAME="/lark-mcp-on-agentcore/alarm-webhook-url"
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

# 选择区域 — remember previous choice
PREV_REGION=""
if [ -f "$DEPLOY_CONFIG" ]; then
  PREV_REGION=$(grep '^REGION=' "$DEPLOY_CONFIG" 2>/dev/null | cut -d= -f2- || echo "")
fi
REGION_SELECTED=""
if [ -n "$PREV_REGION" ] && [ -t 0 ]; then
  echo ""
  info "$(t region_existing "$PREV_REGION")"
  if confirm "${L[region_keep]}"; then
    REGION="$PREV_REGION"
    REGION_SELECTED=1
  fi
fi
if [ -z "$REGION_SELECTED" ]; then
  echo ""
  echo "  ${L[select_region]}"
  echo ""
  pick _REGION_PICK \
    "us-west-2        Oregon" \
    "us-east-1        Virginia" \
    "ap-southeast-1   Singapore" \
    "ap-northeast-1   Tokyo" \
    "ap-southeast-2   Sydney" \
    "ap-south-1       Mumbai" \
    "eu-west-1        Ireland" \
    "eu-central-1     Frankfurt" \
    "me-central-1     UAE" \
    "${L[manual_input]}"
  # Extract region code (first word)
  REGION=$(echo "$_REGION_PICK" | awk '{print $1}')
  if [ "$REGION" = "${L[manual_input]}" ]; then
    ask "${L[ask_region]}" REGION
  fi
fi

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
for STACK_NAME in LarkMcpOnAgentCoreOAuth LarkMcpOnAgentCoreRuntime; do
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
    warn "Stack ${STACK_NAME} status: ${STACK_STATUS}, deleting..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
  fi
done

# WAF lives in us-east-1 regardless of deploy region.
WAF_STATUS=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreWaf --region "us-east-1" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
# H4: if user opted out of WAF this run but a WAF stack from a prior run still
# exists in any healthy state, destroy it before the new deploy so it doesn't
# silently keep charging.
if [ "${SKIP_WAF:-0}" = "1" ] && [ "$WAF_STATUS" != "NOT_FOUND" ] && \
   [ "$WAF_STATUS" != "DELETE_IN_PROGRESS" ] && \
   [ "$WAF_STATUS" != "DELETE_COMPLETE" ]; then
  warn "WAF disabled this run but Stack LarkMcpOnAgentCoreWaf still exists (${WAF_STATUS}). Destroying..."
  ( cd "${PROJECT_DIR}/infra" && AWS_REGION="us-east-1" SKIP_WAF=0 npx cdk destroy LarkMcpOnAgentCoreWaf --force ) || \
    warn "WAF stack destroy failed; manual cleanup may be required."
  WAF_STATUS="NOT_FOUND"
fi
if [ "$WAF_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$WAF_STATUS" = "DELETE_FAILED" ]; then
  warn "Stack LarkMcpOnAgentCoreWaf status: ${WAF_STATUS}, deleting..."
  aws cloudformation delete-stack --stack-name LarkMcpOnAgentCoreWaf --region "us-east-1" 2>/dev/null || true
  aws cloudformation wait stack-delete-complete --stack-name LarkMcpOnAgentCoreWaf --region "us-east-1" 2>/dev/null || true
fi

for SECRET_NAME in "lark-mcp-on-agentcore/feishu-app"; do
  SECRET_STATUS=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" \
    --query 'DeletedDate' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$SECRET_STATUS" != "NOT_FOUND" ] && [ "$SECRET_STATUS" != "None" ]; then
    info "Cleaning pending-delete secret: ${SECRET_NAME}"
    aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
      --force-delete-without-recovery 2>/dev/null || true
  elif [ "$SECRET_STATUS" = "None" ]; then
    OWNING_STACK=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region "$REGION" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$OWNING_STACK" = "NOT_FOUND" ]; then
      warn "Orphaned secret ${SECRET_NAME}, cleaning..."
      aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
        --force-delete-without-recovery 2>/dev/null || true
    fi
  fi
done

SSM_EXISTS=$(aws ssm get-parameter --name "/lark-mcp-on-agentcore/state-secret" --region "$REGION" \
  --query 'Parameter.Name' --output text 2>/dev/null || echo "NOT_FOUND")
OAUTH_STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$SSM_EXISTS" != "NOT_FOUND" ] && [ "$OAUTH_STACK_EXISTS" = "NOT_FOUND" ]; then
  info "Cleaning orphaned SSM: /lark-mcp-on-agentcore/state-secret"
  aws ssm delete-parameter --name "/lark-mcp-on-agentcore/state-secret" --region "$REGION" 2>/dev/null || true
fi

info "Clean up done ✓"

step step_1
echo ""
info "${L[creating_secrets]}"
SECRET_FILE=$(mktemp); chmod 600 "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE"' EXIT
APP_ID="$APP_ID" APP_SECRET="$APP_SECRET" python3 -c \
  'import json,os; print(json.dumps({"appId":os.environ["APP_ID"],"appSecret":os.environ["APP_SECRET"]}))' > "$SECRET_FILE"
if aws secretsmanager describe-secret --secret-id "lark-mcp-on-agentcore/feishu-app" --region "$REGION" &>/dev/null; then
  aws secretsmanager put-secret-value --secret-id "lark-mcp-on-agentcore/feishu-app" \
    --secret-string "file://$SECRET_FILE" --region "$REGION" >/dev/null 2>&1
  info "Secret updated ✓"
else
  aws secretsmanager create-secret --name "lark-mcp-on-agentcore/feishu-app" \
    --secret-string "file://$SECRET_FILE" --region "$REGION" \
    --tags Key=project,Value=lark-mcp-on-agentcore >/dev/null 2>&1
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

if ! aws ssm get-parameter --name "/lark-mcp-on-agentcore/state-secret" --region "$REGION" &>/dev/null; then
  STATE_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  put_secure_param "/lark-mcp-on-agentcore/state-secret" "$STATE_SECRET_VAL"
  info "State secret created ✓"
else
  STATE_SECRET_VAL=$(aws ssm get-parameter --name "/lark-mcp-on-agentcore/state-secret" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "State secret exists ✓"
fi

if ! aws ssm get-parameter --name "/lark-mcp-on-agentcore/oauth-client-secret" --region "$REGION" &>/dev/null; then
  OAUTH_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  put_secure_param "/lark-mcp-on-agentcore/oauth-client-secret" "$OAUTH_SECRET_VAL"
  info "OAuth Client Secret created ✓"
else
  OAUTH_SECRET_VAL=$(aws ssm get-parameter --name "/lark-mcp-on-agentcore/oauth-client-secret" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "OAuth Client Secret exists ✓"
fi

info "${L[building]}"
cd "${PROJECT_DIR}"
npm install --silent 2>/dev/null
( cd "${PROJECT_DIR}/docker" && npm install --omit=dev --silent --no-audit --no-fund 2>/dev/null )
cd "${PROJECT_DIR}/infra"
npm install --silent 2>/dev/null
export CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-}"
CDK_STACKS=(LarkMcpOnAgentCoreRuntime LarkMcpOnAgentCoreOAuth)
if [ "${SKIP_WAF:-0}" != "1" ]; then
  CDK_STACKS=(LarkMcpOnAgentCoreRuntime LarkMcpOnAgentCoreWaf LarkMcpOnAgentCoreOAuth)
fi
if ! AWS_REGION="$REGION" npx cdk deploy "${CDK_STACKS[@]}" --require-approval never 2>&1 | tee /tmp/cdk-deploy.log; then
  echo ""
  err "${L[cdk_failed]}"
  tail -20 /tmp/cdk-deploy.log
  exit 1
fi

# 提取输出
IMAGE_URI=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ImageUri`].OutputValue' --output text 2>/dev/null || echo "")
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RuntimeRoleArn`].OutputValue' --output text 2>/dev/null || echo "")
OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
REDIRECT_URL=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FeishuRedirectUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -z "$IMAGE_URI" ] || [ -z "$ROLE_ARN" ]; then
  err "${L[cdk_check]}"
  exit 1
fi
info "Image: ${IMAGE_URI}"
info "OAuth: ${OAUTH_ENDPOINT}"

# 设置 OAuth Lambda
OAUTH_FN=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthFunctionName`].OutputValue' --output text 2>/dev/null || echo "")
STATE_SECRET_VAL=$(aws ssm get-parameter --name /lark-mcp-on-agentcore/state-secret --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')
OAUTH_SECRET_VAL=$(aws ssm get-parameter --name /lark-mcp-on-agentcore/oauth-client-secret --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')

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
    python3 -c '
import json, os
vars = {
  "CALLBACK_URL": os.environ["CALLBACK_URL"],
  "SECRET_PREFIX": "lark-mcp-on-agentcore/users",
  "OPENID_PREFIX": "lark-mcp-on-agentcore/openid-map",
  "APP_SECRET_ID": "lark-mcp-on-agentcore/feishu-app",
  "STATE_SECRET_PARAM": "/lark-mcp-on-agentcore/state-secret",
  "OAUTH_CLIENT_ID": "lark-mcp-on-agentcore",
  "OAUTH_CLIENT_SECRET": os.environ["OAUTH_SECRET_VAL"],
  "FEISHU_SCOPES": os.environ.get("FEISHU_SCOPES", ""),
  "CODE_TABLE": "lark-mcp-on-agentcore-oauth-codes",
}
if os.environ.get("CUSTOM_DOMAIN"):
  vars["ALLOWED_DOMAINS"] = os.environ["CUSTOM_DOMAIN"]
print(json.dumps({"Variables": vars}))
' > "$ENV_FILE"
  aws lambda update-function-configuration \
    --function-name "$OAUTH_FN" \
    --environment "file://$ENV_FILE" \
    --region "$REGION" >/dev/null 2>&1
  rm -f "$ENV_FILE"
  info "OAuth Lambda configured ✓"
fi

# AgentCore Runtime
step step_2
RUNTIME_ID=$(APP_ID="$APP_ID" REGION="$REGION" ROLE_ARN="$ROLE_ARN" \
  IMAGE_URI="$IMAGE_URI" OAUTH_ENDPOINT="$OAUTH_ENDPOINT" \
  python3 << 'PYEOF'
import os, boto3, sys
region = os.environ['REGION']
c = boto3.client('bedrock-agentcore-control', region_name=region)
runtime_config = {
    'roleArn': os.environ['ROLE_ARN'],
    'agentRuntimeArtifact': {'containerConfiguration': {'containerUri': os.environ['IMAGE_URI']}},
    'networkConfiguration': {'networkMode': 'PUBLIC'},
    'protocolConfiguration': {'serverProtocol': 'MCP'},
    'requestHeaderConfiguration': {'requestHeaderAllowlist': ['X-User-Access-Token', 'X-Runtime-User-Id', 'X-Incr-Auth-Token']},
    'environmentVariables': {
        'APP_ID': os.environ['APP_ID'],
        'APP_SECRET_ID': 'lark-mcp-on-agentcore/feishu-app',
        'AWS_REGION': region,
        'LARKSUITE_CLI_BRAND': 'feishu',
        'AUTHORIZE_BASE': os.environ['OAUTH_ENDPOINT'],
    },
}
try:
    resp = c.create_agent_runtime(
        agentRuntimeName='lark_mcp_on_agentcore',
        description='Lark MCP Server (lark-cli)',
        tags={'project': 'lark-mcp-on-agentcore'},
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
                if r.get('agentRuntimeName') == 'lark_mcp_on_agentcore':
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
MIDDLEWARE_FN=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`MiddlewareFunctionName`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$MIDDLEWARE_FN" ]; then
  aws lambda update-function-configuration \
    --function-name "$MIDDLEWARE_FN" \
    --environment "Variables={RUNTIME_ARN=${RUNTIME_ARN},SECRET_PREFIX=lark-mcp-on-agentcore/users,STATE_SECRET_PARAM=/lark-mcp-on-agentcore/state-secret,AUTHORIZE_BASE=${OAUTH_ENDPOINT},DEPLOY_REGION=${REGION}}" \
    --region $REGION >/dev/null 2>&1
  info "Middleware configured ✓"
else
  warn "Middleware Lambda not found. Check LarkMcpOnAgentCoreOAuth Stack."
fi

# MCP endpoint
MCP_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`McpEndpoint`].OutputValue' --output text 2>/dev/null || echo "N/A")
DASHBOARD_URL=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
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

# Save deploy config for next run
cat > "$DEPLOY_CONFIG" << CFGEOF
LARK_LANG=${LARK_LANG}
REGION=${REGION}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN:-}
SKIP_WAF=${SKIP_WAF}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-}
CFGEOF
chmod 600 "$DEPLOY_CONFIG"

# OAuth Client 信息
OAUTH_CLIENT_ID="lark-mcp-on-agentcore"
OAUTH_CLIENT_SECRET_VAL="${OAUTH_SECRET_VAL}"

# 保存部署信息
DEPLOY_INFO="${LOCAL_DIR}/deploy-output.md"
umask 077
cat > "$DEPLOY_INFO" << INFOEOF
# Lark MCP on AgentCore - Deployment Info

> Deployed: $(date '+%Y-%m-%d %H:%M:%S')
> Region: ${REGION}
> Account: ${ACCOUNT_ID}

## Quick Desktop Setup

Settings → Capabilities → Browse Connections → Connectors →
Create for your team → Model Context Protocol → No, create new

Connection info:
| Field | Value |
|-------|-------|
| Name | Feishu Remote MCP |
| MCP server endpoint | ${MCP_ENDPOINT} |
| Connection type | public |

OAuth config (after Create integration):
| Field | Value |
|-------|-------|
| Client ID | ${OAUTH_CLIENT_ID} |
| Client Secret | ${OAUTH_CLIENT_SECRET_VAL} |
| Token URL | ${OAUTH_ENDPOINT}/token |
| Authorization URL | ${OAUTH_ENDPOINT}/authorize |

Save → Connect → Authorize in browser → Connected.

## Feishu App Redirect URL

Open Feishu app security settings:
https://open.feishu.cn/app/${APP_ID}/safe

Add redirect URL:
${REDIRECT_URL}

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
echo -e "${YELLOW}  ${L[next_steps]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}  ${L[step1_title]}${NC}"
echo ""
echo "    ${L[step1_open]}"
echo "    https://open.feishu.cn/app/${APP_ID}/safe"
echo ""
echo "    ${L[step1_add]}"
echo "    ${REDIRECT_URL}"
echo ""
echo -e "${CYAN}  ${L[step2_title]}${NC}"
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
