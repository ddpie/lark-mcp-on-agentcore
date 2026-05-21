#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# End-to-end test script for lark-mcp-on-agentcore
#
# Tests all deployed components. Run after ./scripts/deploy.sh completes.
#
# Usage:
#   ./scripts/test-e2e.sh [--runtime-arn <arn>] [--oauth-endpoint <url>]
#
# Or set env vars:
#   RUNTIME_ARN=arn:aws:bedrock-agentcore:...
#   OAUTH_ENDPOINT=https://xxx.cloudfront.net
#   TEST_USER_ID=test-user
# ==============================================================================

REGION="${AWS_REGION:-us-west-2}"
RUNTIME_ARN="${RUNTIME_ARN:-}"
OAUTH_ENDPOINT="${OAUTH_ENDPOINT:-}"
TEST_USER_ID="${TEST_USER_ID:-e2e-test-user}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --runtime-arn) RUNTIME_ARN="$2"; shift 2 ;;
    --oauth-endpoint) OAUTH_ENDPOINT="$2"; shift 2 ;;
    --user-id) TEST_USER_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Auto-detect from CloudFormation if not provided
if [ -z "$OAUTH_ENDPOINT" ]; then
  OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
fi

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  \033[32m✓ $1\033[0m"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[31m✗ $1\033[0m"; FAIL=$((FAIL+1)); }
skip() { echo -e "  \033[33m⊘ $1\033[0m"; SKIP=$((SKIP+1)); }

echo ""
echo "=== Lark MCP on AgentCore - E2E Tests ==="
echo "  Region: ${REGION}"
echo "  OAuth:  ${OAUTH_ENDPOINT:-<not set>}"
echo "  Runtime: ${RUNTIME_ARN:-<not set>}"
echo ""

# Test 1: OAuth /authorize endpoint
echo "── OAuth Flow ──"
if [ -n "$OAUTH_ENDPOINT" ]; then
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/authorize?user_id=${TEST_USER_ID}")
  if [ "$HTTP" = "302" ]; then pass "/authorize → 302 redirect"; else fail "/authorize → HTTP ${HTTP} (expected 302)"; fi

  # Test HMAC state in redirect
  REDIRECT=$(curl -s -o /dev/null -w "%{redirect_url}" "${OAUTH_ENDPOINT}/authorize?user_id=${TEST_USER_ID}")
  if echo "$REDIRECT" | grep -q "state="; then pass "/authorize includes HMAC state"; else fail "/authorize missing state"; fi

  # Test tampered state rejection
  TAMPER=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/callback?code=fake&state=dGFtcGVyZWQ6MTIzOmZha2U")
  if [ "$TAMPER" = "403" ]; then pass "/callback rejects tampered state"; else fail "/callback → HTTP ${TAMPER} (expected 403)"; fi

  # Test /token (IAM protected)
  TOKEN_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/token?user_id=test")
  if [ "$TOKEN_HTTP" = "403" ] || [ "$TOKEN_HTTP" = "401" ]; then pass "/token blocked from public"; else fail "/token → HTTP ${TOKEN_HTTP} (expected 403)"; fi
else
  skip "OAuth endpoint not configured"
fi

# Test 2: AgentCore Runtime
echo ""
echo "── AgentCore Runtime ──"
if [ -n "$RUNTIME_ARN" ]; then
  INIT_RESULT=$(python3 -c "
import boto3, json, urllib.parse, urllib.request
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
url = f'https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/{urllib.parse.quote(\"${RUNTIME_ARN}\", safe=\"\")}/invocations'
body = json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'e2e-test','version':'1'}}})
request = AWSRequest(method='POST', url=url, data=body, headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
SigV4Auth(creds, 'bedrock-agentcore', '${REGION}').add_auth(request)
req = urllib.request.Request(request.url, data=body.encode(), headers=dict(request.headers), method='POST')
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        r = resp.read().decode()
        print('OK' if 'serverInfo' in r else 'FAIL')
except Exception as e:
    print(f'ERROR:{str(e)[:80]}')
" 2>&1)

  if [ "$INIT_RESULT" = "OK" ]; then pass "MCP initialize via AgentCore"; else fail "MCP initialize: ${INIT_RESULT}"; fi

  # Test tools/list
  TOOLS_RESULT=$(python3 -c "
import boto3, json, re, urllib.parse, urllib.request
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
url = f'https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/{urllib.parse.quote(\"${RUNTIME_ARN}\", safe=\"\")}/invocations'
body = json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/list','params':{}})
request = AWSRequest(method='POST', url=url, data=body, headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
SigV4Auth(creds, 'bedrock-agentcore', '${REGION}').add_auth(request)
req = urllib.request.Request(request.url, data=body.encode(), headers=dict(request.headers), method='POST')
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        r = resp.read().decode()
        tools = re.findall(r'\"name\":\"([^\"]+)\"', r)
        print(f'{len(tools)}')
except: print('0')
" 2>&1)

  if [ "${TOOLS_RESULT:-0}" -gt "0" ]; then pass "tools/list returns ${TOOLS_RESULT} tools"; else fail "tools/list returned 0 tools"; fi

  # Test with user token from SM (if exists)
  TOKEN_TEST=$(python3 -c "
import boto3, json, urllib.parse, urllib.request
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
sm = boto3.client('secretsmanager', region_name='${REGION}')
try:
    secret = json.loads(sm.get_secret_value(SecretId='lark-mcp/users/${TEST_USER_ID}')['SecretString'])
    uat = secret['access_token']
except:
    print('NO_TOKEN')
    exit(0)
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
url = f'https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/{urllib.parse.quote(\"${RUNTIME_ARN}\", safe=\"\")}/invocations'
body = json.dumps({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'im_v1_chat_list','arguments':{}}})
request = AWSRequest(method='POST', url=url, data=body, headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream','X-User-Access-Token':uat})
SigV4Auth(creds, 'bedrock-agentcore', '${REGION}').add_auth(request)
req = urllib.request.Request(request.url, data=body.encode(), headers=dict(request.headers), method='POST')
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        r = resp.read().decode()
        if 'items' in r: print('USER_OK')
        else: print('USER_FAIL')
except: print('USER_ERROR')
" 2>&1)

  case "$TOKEN_TEST" in
    USER_OK) pass "tools/call with user token (from SM)" ;;
    NO_TOKEN) skip "No token in SM for ${TEST_USER_ID} (authorize first)" ;;
    *) fail "User token call: ${TOKEN_TEST}" ;;
  esac
else
  skip "Runtime ARN not configured"
fi

# Test 3: Secrets Manager token storage
echo ""
echo "── Token Storage ──"
SM_TEST=$(aws secretsmanager list-secrets --region $REGION --filters "Key=name,Values=lark-mcp/users" --query 'SecretList | length(@)' --output text 2>/dev/null || echo "0")
if [ "${SM_TEST:-0}" -gt "0" ]; then pass "Secrets Manager has ${SM_TEST} user token(s)"; else skip "No user tokens stored yet"; fi

# Test 4: EventBridge rule
echo ""
echo "── Token Refresh ──"
EB_STATE=$(aws events describe-rule --name lark-mcp-token-refresh --region $REGION --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$EB_STATE" = "ENABLED" ]; then pass "EventBridge refresh rule: ENABLED"; else skip "EventBridge rule: ${EB_STATE}"; fi

# Summary
echo ""
echo "═══════════════════════════════════"
echo "  Pass: ${PASS}  Fail: ${FAIL}  Skip: ${SKIP}"
echo "═══════════════════════════════════"
echo ""

if [ $FAIL -gt 0 ]; then exit 1; fi
