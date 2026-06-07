#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_DIR="${PROJECT_DIR}/.local"
REGION="${AWS_REGION:-us-west-2}"

# --app <slug>: operate on a specific app (empty = default app, byte-identical
# names). Parse it out of the args before the subcommand so `ops.sh list-users
# --app team-a` and `ops.sh --app team-a list-users` both work.
APP_SLUG="${APP_SLUG:-}"
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --app)   APP_SLUG="${2:-}"; shift 2 ;;
    --app=*) APP_SLUG="${1#--app=}"; shift ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

# shellcheck source=lib/slug.sh
source "${SCRIPT_DIR}/lib/slug.sh"
resolve_slug "$APP_SLUG" || exit 1
APPS_REGISTRY="${LOCAL_DIR}/apps.json"
export APPS_REGISTRY
# shellcheck source=lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"

get_oauth_fn() {
  aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`OAuthFunctionName`].OutputValue' --output text 2>/dev/null || echo ""
}

# list_user_secret_names is provided by scripts/lib/slug.sh (shared with
# teardown.sh) so the Killer Fix #3 single-segment screen has one source of truth.

case "${1:-help}" in
  list-users)
    echo "已授权用户 (app: ${SLUG:-default}):"
    list_user_secret_names | sed 's#^#  #' || true
    ;;
  list-apps)
    echo "已部署应用:"
    echo "  default  (lark_mcp_on_agentcore)"
    if [ -f "$APPS_REGISTRY" ]; then
      while IFS= read -r s; do
        [ -z "$s" ] && continue
        printf '  %s  (%s)\n' "$(get_app_alias "$s")" "$s"
      done < <(list_app_slugs)
    fi
    ;;
  rename)
    NEW_ALIAS="${2:?用法: ops.sh rename --app <slug> <new-alias>}"
    if [ -z "$SLUG" ]; then echo "  rename 需要 --app <slug>(默认应用无别名)"; exit 1; fi
    if rename_alias "$SLUG" "$NEW_ALIAS"; then
      # Refresh the alarm-webhook Lambda's APP_ALIAS so alert cards show the new name.
      WEBHOOK_FN=$(aws cloudformation describe-stacks --stack-name "$OAUTH_STACK" --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`AlarmWebhookFunctionName`].OutputValue' --output text 2>/dev/null || echo "")
      if [ -n "$WEBHOOK_FN" ] && [ "$WEBHOOK_FN" != "None" ]; then
        CURRENT_ENV=$(aws lambda get-function-configuration --function-name "$WEBHOOK_FN" --region "$REGION" \
          --query 'Environment.Variables' --output json 2>/dev/null || echo '{}')
        ENV_FILE=$(mktemp); chmod 600 "$ENV_FILE"
        NEW_ALIAS="$NEW_ALIAS" python3 -c '
import json, os, sys
env = json.loads(sys.stdin.read() or "{}")
env["APP_ALIAS"] = os.environ["NEW_ALIAS"]
print(json.dumps({"Variables": env}))
' <<< "$CURRENT_ENV" > "$ENV_FILE"
        aws lambda update-function-configuration --function-name "$WEBHOOK_FN" \
          --environment "file://$ENV_FILE" --region "$REGION" >/dev/null 2>&1 || true
        rm -f "$ENV_FILE"
      fi
      echo "  已重命名为 '${NEW_ALIAS}' ✓"
    else
      echo "  别名 '${NEW_ALIAS}' 已被占用,请换一个。"; exit 1
    fi
    ;;
  revoke)
    USER="${2:?用法: ops.sh revoke --app <slug> <user_id>}"
    # user_id is a single Feishu open_id / hex segment — never contains '/'.
    # Reject any slash so a crafted id like 'team-a/ou_victim' can't escape this
    # app's namespace and force-delete another app's nested user secret (the
    # IAM/runtime isolation boundary; mirrors the listAllUserSecrets [^/]+ screen).
    case "$USER" in
      */*|"") echo "  无效的 user_id: '${USER}'(不能包含 '/')" >&2; exit 1 ;;
    esac
    SECRET_ID="${SECRET_USERS_PREFIX}/${USER}"
    echo "  将永久删除密钥: ${SECRET_ID}"
    read -rp "  确认撤销 ${USER} (app: ${SLUG:-default}) 的 Token? (y/N) " CONFIRM
    if [[ "$CONFIRM" =~ ^[yY] ]]; then
      aws secretsmanager delete-secret --secret-id "$SECRET_ID" --force-delete-without-recovery --region "$REGION" 2>&1
      echo "  已撤销 ✓"
    fi
    ;;
  refresh-all)
    echo "触发手动刷新 (app: ${SLUG:-default})..."
    LAMBDA_FN=$(get_oauth_fn)
    if [ -z "$LAMBDA_FN" ]; then echo "  未找到 OAuth Lambda"; exit 1; fi
    aws lambda invoke --function-name "$LAMBDA_FN" --payload '{"source":"aws.events"}' --region "$REGION" /tmp/refresh-out.json 2>&1 | head -2
    python3 -m json.tool < /tmp/refresh-out.json
    ;;
  logs)
    echo "最近 Lambda 日志 (app: ${SLUG:-default}):"
    LAMBDA_FN=$(get_oauth_fn)
    if [ -z "$LAMBDA_FN" ]; then echo "  未找到 OAuth Lambda"; exit 1; fi
    aws logs tail "/aws/lambda/${LAMBDA_FN}" --region "$REGION" --since 1h --format short 2>/dev/null | tail -20 || echo "  未找到日志"
    ;;
  status)
    echo "=== 系统状态 (app: ${SLUG:-default}) ==="
    echo ""
    USERS=$(list_user_secret_names | grep -c . || true)
    echo "  已授权用户: ${USERS}"
    echo "  Runtime:    ${RUNTIME_NAME}"
    EB_RULE=$(aws events list-rules --name-prefix "$OAUTH_STACK" --region "$REGION" --query 'Rules[0].Name' --output text 2>/dev/null || echo "")
    if [ -z "$EB_RULE" ] || [ "$EB_RULE" = "None" ]; then EB="未找到"; else
    EB=$(aws events describe-rule --name "$EB_RULE" --region "$REGION" --query 'State' --output text 2>/dev/null || echo "未找到"); fi
    echo "  Token 刷新:  ${EB}"
    echo ""
    ;;
  destroy)
    echo "销毁 AgentCore Runtime (app: ${SLUG:-default})..."
    RUNTIME_ID=$(RUNTIME_NAME="$RUNTIME_NAME" REGION="$REGION" python3 -c "
import boto3, os
c = boto3.client('bedrock-agentcore-control', region_name=os.environ['REGION'])
target = os.environ['RUNTIME_NAME']
next_token = None
while True:
    kwargs = {'nextToken': next_token} if next_token else {}
    resp = c.list_agent_runtimes(**kwargs)
    for r in resp.get('agentRuntimes', []):
        if r.get('agentRuntimeName') == target:
            print(r['agentRuntimeId']); exit(0)
    next_token = resp.get('nextToken')
    if not next_token: break
" 2>/dev/null)
    if [ -n "$RUNTIME_ID" ]; then
      read -rp "  确认删除 Runtime ${RUNTIME_ID} (${RUNTIME_NAME})? (y/N) " CONFIRM
      if [[ "$CONFIRM" =~ ^[yY] ]]; then
        RUNTIME_ID="$RUNTIME_ID" REGION="$REGION" python3 -c "
import boto3, time, os
c = boto3.client('bedrock-agentcore-control', region_name=os.environ['REGION'])
rid = os.environ['RUNTIME_ID']
try: c.delete_agent_runtime_endpoint(agentRuntimeId=rid, endpointName='ep')
except Exception: pass
time.sleep(3)
c.delete_agent_runtime(agentRuntimeId=rid)
print('  已删除 ✓')
"
      fi
    else
      echo "  未找到 AgentCore Runtime (${RUNTIME_NAME})。"
    fi
    ;;
  rotate-secret)
    echo "轮换 OAuth Client Secret (app: ${SLUG:-default})..."
    NEW_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    SEC_FILE=$(mktemp); chmod 600 "$SEC_FILE"
    printf '%s' "$NEW_SECRET" > "$SEC_FILE"
    aws ssm put-parameter --name "$OAUTH_SECRET_PARAM" --value "file://$SEC_FILE" \
      --type SecureString --overwrite --region "$REGION" >/dev/null 2>&1
    rm -f "$SEC_FILE"
    aws ssm add-tags-to-resource \
      --resource-type Parameter \
      --resource-id "$OAUTH_SECRET_PARAM" \
      --tags "Key=project,Value=lark-mcp-on-agentcore" \
      --region "$REGION" >/dev/null 2>&1 || true
    LAMBDA_FN=$(get_oauth_fn)
    if [ -n "$LAMBDA_FN" ]; then
      CURRENT_ENV=$(aws lambda get-function-configuration --function-name "$LAMBDA_FN" --region "$REGION" \
        --query 'Environment.Variables' --output json 2>/dev/null)
      ENV_FILE=$(mktemp); chmod 600 "$ENV_FILE"
      NEW_SECRET="$NEW_SECRET" python3 -c '
import json, os, sys
env = json.loads(sys.stdin.read())
env["OAUTH_CLIENT_SECRET"] = os.environ["NEW_SECRET"]
print(json.dumps({"Variables": env}))
' <<< "$CURRENT_ENV" > "$ENV_FILE"
      aws lambda update-function-configuration --function-name "$LAMBDA_FN" \
        --environment "file://$ENV_FILE" --region "$REGION" >/dev/null 2>&1
      rm -f "$ENV_FILE"
    fi
    echo ""
    echo "  新 Client Secret: ${NEW_SECRET:0:8}..."
    echo ""
    echo "  ⚠ 注意:"
    echo "    1. 已发放的 MCP Token 仍然有效 (STATE_SECRET 未变)"
    echo "    2. 请更新 Quick Desktop connector 的 Client Secret"
    echo ""
    echo "  已更新 ✓"
    ;;
  help|*)
    echo "用法: ./scripts/ops.sh [--app <slug>] <命令>"
    echo ""
    echo "命令:"
    echo "  list-users     列出所有已授权用户"
    echo "  list-apps      列出所有已部署应用 (别名 + slug)"
    echo "  rename         重命名应用别名 (--app <slug> <new-alias>)"
    echo "  revoke         撤销用户 Token"
    echo "  refresh-all    手动触发 Token 刷新"
    echo "  logs           查看最近 Lambda 日志"
    echo "  status         系统概览"
    echo "  rotate-secret  轮换 OAuth Client Secret"
    echo "  destroy        删除 AgentCore Runtime (仅 Runtime;完整销毁请用 ./scripts/teardown.sh)"
    echo ""
    echo "  --app <slug>   指定应用 (默认应用可省略)"
    ;;
esac
