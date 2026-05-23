#!/usr/bin/env bash
# Tear down all AWS resources for this deployment.
# Order: AgentCore Runtime → CDK stacks (deploy region) → WAF stack (us-east-1) →
# user-token Secrets Manager entries (optional).

set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step()  { echo -e "\n${GREEN}=== $1 ===${NC}\n"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }

# Top-level confirmation. CDK destroys run with --force, so this is the
# only check before destructive actions begin. Skip with TEARDOWN_YES=1.
if [ "${TEARDOWN_YES:-0}" != "1" ]; then
  echo ""
  warn "This will destroy the AgentCore Runtime and all CDK stacks for this deployment."
  warn "  Region:           $REGION"
  warn "  WAF (us-east-1):  $([ "${SKIP_WAF:-0}" = "1" ] && echo skip || echo destroy)"
  warn "  User tokens:      will prompt before deleting"
  read -rp "  Continue? (type 'yes' to proceed): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "  Aborted."
    exit 0
  fi
fi

# 1. AgentCore Runtime + Endpoint (not managed by CDK).
step "AgentCore Runtime"
RUNTIME_ID=$(python3 -c "
import boto3
c = boto3.client('bedrock-agentcore-control', region_name='$REGION')
nt = None
while True:
    kw = {'nextToken': nt} if nt else {}
    r = c.list_agent_runtimes(**kw)
    for x in r.get('agentRuntimes', []):
        if x.get('agentRuntimeName') == 'lark-mcp-on-agentcore':
            print(x['agentRuntimeId']); exit(0)
    nt = r.get('nextToken')
    if not nt: break
" 2>/dev/null || echo "")

if [ -n "$RUNTIME_ID" ]; then
  echo "  Found Runtime: $RUNTIME_ID"
  python3 -c "
import boto3, time
c = boto3.client('bedrock-agentcore-control', region_name='$REGION')
try: c.delete_agent_runtime_endpoint(agentRuntimeId='$RUNTIME_ID', endpointName='ep')
except Exception as e: print(f'  endpoint delete: {e}')
time.sleep(3)
try:
    c.delete_agent_runtime(agentRuntimeId='$RUNTIME_ID')
    print('  Runtime deleted')
except Exception as e: print(f'  runtime delete failed: {e}')
"
else
  echo "  No Runtime found, skipping"
fi

# 2. CDK stacks.
step "CDK stacks ($REGION)"
( cd "${PROJECT_DIR}/infra" && AWS_REGION="$REGION" npx cdk destroy LarkMcpOnAgentCoreOAuth LarkMcpOnAgentCoreRuntime --force ) || warn "Some CDK destroy steps failed"

if [ "${SKIP_WAF:-0}" != "1" ]; then
  step "CDK stacks (us-east-1, WAF)"
  ( cd "${PROJECT_DIR}/infra" && AWS_REGION="us-east-1" SKIP_WAF=0 npx cdk destroy LarkMcpOnAgentCoreWaf --force ) || warn "WAF destroy failed"
fi

# 3. User-token secrets — confirm before deleting (real authorizations).
step "User token secrets"
USER_COUNT=$(aws secretsmanager list-secrets --region "$REGION" \
  --filters "Key=name,Values=lark-mcp-on-agentcore/users" \
  --query 'SecretList | length(@)' --output text 2>/dev/null || echo "0")
if [ "${USER_COUNT:-0}" -gt 0 ]; then
  warn "Found ${USER_COUNT} user-token secret(s)."
  read -rp "  Delete all user tokens? Users will need to re-authorize. (type 'yes' to proceed) " confirm
  if [ "$confirm" = "yes" ]; then
    aws secretsmanager list-secrets --region "$REGION" \
      --filters "Key=name,Values=lark-mcp-on-agentcore/users" \
      --query 'SecretList[].Name' --output text | tr '\t' '\n' | while read -r name; do
      [ -n "$name" ] && aws secretsmanager delete-secret --secret-id "$name" \
        --force-delete-without-recovery --region "$REGION" >/dev/null 2>&1 || true
    done
    echo "  User tokens deleted"
  fi
fi

# 4. App secret + state secret + openid mappings (kept by default).
echo ""
echo "  Remaining (preserved by default):"
echo "    - secret  lark-mcp-on-agentcore/feishu-app"
echo "    - ssm     /lark-mcp-on-agentcore/state-secret"
echo "    - ssm     /lark-mcp-on-agentcore/oauth-client-secret"
echo "    - secrets lark-mcp-on-agentcore/openid-map/*"
echo ""
echo "  To purge them too:"
echo "    aws secretsmanager delete-secret --secret-id lark-mcp-on-agentcore/feishu-app --force-delete-without-recovery --region $REGION"
echo "    aws ssm delete-parameter --name /lark-mcp-on-agentcore/state-secret --region $REGION"
echo "    aws ssm delete-parameter --name /lark-mcp-on-agentcore/oauth-client-secret --region $REGION"
echo ""
echo -e "${GREEN}Teardown complete.${NC}"
