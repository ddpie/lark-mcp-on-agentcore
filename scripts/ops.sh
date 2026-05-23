#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
SECRET_PREFIX="lark-mcp-on-agentcore/users"

get_oauth_fn() {
  aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`OAuthFunctionName`].OutputValue' --output text 2>/dev/null || echo ""
}

case "${1:-help}" in
  list-users)
    echo "已授权用户:"
    aws secretsmanager list-secrets --region $REGION \
      --filters "Key=name,Values=${SECRET_PREFIX}" \
      --query 'SecretList[*].{Name:Name,Updated:LastChangedDate}' --output table
    ;;
  revoke)
    USER="${2:?用法: ops.sh revoke <user_id>}"
    read -rp "  确认撤销 ${USER} 的 Token? (y/N) " CONFIRM
    if [[ "$CONFIRM" =~ ^[yY] ]]; then
      aws secretsmanager delete-secret --secret-id "${SECRET_PREFIX}/${USER}" --force-delete-without-recovery --region $REGION 2>&1
      echo "  已撤销 ✓"
    fi
    ;;
  refresh-all)
    echo "触发手动刷新..."
    LAMBDA_FN=$(get_oauth_fn)
    if [ -z "$LAMBDA_FN" ]; then echo "  未找到 OAuth Lambda"; exit 1; fi
    aws lambda invoke --function-name "$LAMBDA_FN" --payload '{"source":"aws.events"}' --region $REGION /tmp/refresh-out.json 2>&1 | head -2
    cat /tmp/refresh-out.json | python3 -m json.tool
    ;;
  logs)
    echo "最近 Lambda 日志:"
    LAMBDA_FN=$(get_oauth_fn)
    if [ -z "$LAMBDA_FN" ]; then echo "  未找到 OAuth Lambda"; exit 1; fi
    aws logs tail "/aws/lambda/${LAMBDA_FN}" --region $REGION --since 1h --format short 2>/dev/null | tail -20 || echo "  未找到日志"
    ;;
  status)
    echo "=== 系统状态 ==="
    echo ""
    USERS=$(aws secretsmanager list-secrets --region $REGION --filters "Key=name,Values=${SECRET_PREFIX}" --query 'SecretList | length(@)' --output text 2>/dev/null || echo "?")
    echo "  已授权用户: ${USERS}"
    EB_RULE=$(aws events list-rules --name-prefix LarkMcpOnAgentCoreOAuth --region $REGION --query 'Rules[0].Name' --output text 2>/dev/null || echo "")
    if [ -z "$EB_RULE" ] || [ "$EB_RULE" = "None" ]; then EB="未找到"; else
    EB=$(aws events describe-rule --name "$EB_RULE" --region $REGION --query 'State' --output text 2>/dev/null || echo "未找到"); fi
    echo "  Token 刷新:  ${EB}"
    echo ""
    ;;
  destroy)
    echo "销毁 AgentCore Runtime..."
    RUNTIME_ID=$(python3 -c "
import boto3
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
next_token = None
while True:
    kwargs = {'nextToken': next_token} if next_token else {}
    resp = c.list_agent_runtimes(**kwargs)
    for r in resp.get('agentRuntimes', []):
        if r.get('agentRuntimeName') == 'lark_mcp_on_agentcore':
            print(r['agentRuntimeId']); exit(0)
    next_token = resp.get('nextToken')
    if not next_token: break
" 2>/dev/null)
    if [ -n "$RUNTIME_ID" ]; then
      read -rp "  确认删除 Runtime ${RUNTIME_ID}? (y/N) " CONFIRM
      if [[ "$CONFIRM" =~ ^[yY] ]]; then
        python3 -c "
import boto3, time
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try: c.delete_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep')
except: pass
time.sleep(3)
c.delete_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
print('  已删除 ✓')
"
      fi
    else
      echo "  未找到 AgentCore Runtime。"
    fi
    ;;
  rotate-secret)
    echo "轮换 OAuth Client Secret..."
    NEW_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    SEC_FILE=$(mktemp); chmod 600 "$SEC_FILE"
    printf '%s' "$NEW_SECRET" > "$SEC_FILE"
    aws ssm put-parameter --name "/lark-mcp-on-agentcore/oauth-client-secret" --value "file://$SEC_FILE" \
      --type SecureString --overwrite --region "$REGION" >/dev/null 2>&1
    rm -f "$SEC_FILE"
    # Re-apply project tag (idempotent). put-parameter --overwrite preserves
    # existing tags, but if the parameter was recreated out-of-band and lacked
    # the project tag, this restores it.
    aws ssm add-tags-to-resource \
      --resource-type Parameter \
      --resource-id "/lark-mcp-on-agentcore/oauth-client-secret" \
      --tags "Key=project,Value=lark-mcp-on-agentcore" \
      --region "$REGION" >/dev/null 2>&1 || true
    # Update OAuth Lambda env (only OAUTH_CLIENT_SECRET, not STATE_SECRET)
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
    echo "用法: ./scripts/ops.sh <命令>"
    echo ""
    echo "命令:"
    echo "  list-users     列出所有已授权用户"
    echo "  revoke         撤销用户 Token"
    echo "  refresh-all    手动触发 Token 刷新"
    echo "  logs           查看最近 Lambda 日志"
    echo "  status         系统概览"
    echo "  rotate-secret  轮换 OAuth Client Secret"
    echo "  destroy        删除 AgentCore Runtime (仅 Runtime;完整销毁请用 ./scripts/teardown.sh)"
    ;;
esac
