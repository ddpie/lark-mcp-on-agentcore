#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
SECRET_PREFIX="lark-mcp/users"

case "${1:-help}" in
  list-users)
    echo "Authorized users:"
    aws secretsmanager list-secrets --region $REGION \
      --filters "Key=name,Values=${SECRET_PREFIX}" \
      --query 'SecretList[*].{Name:Name,Updated:LastChangedDate}' --output table
    ;;
  check-token)
    USER="${2:?Usage: ops.sh check-token <user_id>}"
    python3 -c "
import boto3, json
from datetime import datetime
sm = boto3.client('secretsmanager', region_name='${REGION}')
try:
    resp = sm.get_secret_value(SecretId='${SECRET_PREFIX}/${USER}')
    d = json.loads(resp['SecretString'])
    exp = datetime.fromtimestamp(d['expires_at'])
    remaining = d['expires_at'] - __import__('time').time()
    status = '✓ valid' if remaining > 0 else '✗ expired'
    print(f'  User: ${USER}')
    print(f'  Status: {status}')
    print(f'  Expires: {exp} ({int(remaining/60)}min remaining)')
    print(f'  Token: {d[\"access_token\"][:20]}...')
except Exception as e:
    print(f'  Not found or error: {e}')
"
    ;;
  revoke)
    USER="${2:?Usage: ops.sh revoke <user_id>}"
    read -rp "  Revoke token for ${USER}? (y/N) " CONFIRM
    if [[ "$CONFIRM" =~ ^[yY] ]]; then
      aws secretsmanager delete-secret --secret-id "${SECRET_PREFIX}/${USER}" --force-delete-without-recovery --region $REGION 2>&1
      echo "  Revoked ✓"
    fi
    ;;
  refresh-all)
    echo "Triggering manual refresh..."
    aws lambda invoke --function-name lark-token-shim --payload '{"source":"aws.events"}' --region $REGION /tmp/refresh-out.json 2>&1 | head -2
    cat /tmp/refresh-out.json | python3 -m json.tool
    ;;
  logs)
    echo "Recent Lambda logs:"
    aws logs tail "/aws/lambda/lark-token-shim" --region $REGION --since 1h --format short 2>/dev/null | tail -20 || echo "  No logs found"
    ;;
  status)
    echo "=== System Status ==="
    echo ""
    USERS=$(aws secretsmanager list-secrets --region $REGION --filters "Key=name,Values=${SECRET_PREFIX}" --query 'SecretList | length(@)' --output text 2>/dev/null || echo "?")
    echo "  Authorized users: ${USERS}"
    EB=$(aws events describe-rule --name lark-mcp-token-refresh --region $REGION --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
    echo "  Token refresh:    ${EB}"
    echo ""
    ;;
  destroy)
    echo "Destroying AgentCore Runtime..."
    RUNTIME_ID=$(python3 -c "
import boto3
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
runtimes = c.list_agent_runtimes()
for r in runtimes.get('agentRuntimeSummaries', []):
    if 'larkmcp' in r.get('agentRuntimeName', ''):
        print(r['agentRuntimeId']); break
" 2>/dev/null)
    if [ -n "$RUNTIME_ID" ]; then
      read -rp "  Delete runtime ${RUNTIME_ID}? (y/N) " CONFIRM
      if [[ "$CONFIRM" =~ ^[yY] ]]; then
        python3 -c "
import boto3, time
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try: c.delete_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep')
except: pass
time.sleep(3)
c.delete_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
print('  Deleted ✓')
"
      fi
    else
      echo "  No AgentCore Runtime found."
    fi
    ;;
  help|*)
    echo "Usage: ./scripts/ops.sh <command>"
    echo ""
    echo "Commands:"
    echo "  list-users     List all authorized users"
    echo "  check-token    Check token status for a user"
    echo "  revoke         Revoke a user's token"
    echo "  refresh-all    Manually trigger token refresh"
    echo "  logs           Show recent Lambda logs"
    echo "  status         System overview"
    echo "  destroy        Delete AgentCore Runtime"
    ;;
esac
