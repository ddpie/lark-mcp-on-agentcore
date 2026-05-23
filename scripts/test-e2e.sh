#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 端到端测试脚本
#
# 在 ./scripts/deploy.sh 完成后运行，验证所有已部署组件。
#
# 用法:
#   ./scripts/test-e2e.sh [--runtime-arn <arn>] [--oauth-endpoint <url>]
#
# 或设置环境变量:
#   RUNTIME_ARN=arn:aws:bedrock-agentcore:...
#   OAUTH_ENDPOINT=https://xxx.cloudfront.net
#   TEST_USER_ID=test-user
# ==============================================================================

REGION="${AWS_REGION:-us-west-2}"
RUNTIME_ARN="${RUNTIME_ARN:-}"
OAUTH_ENDPOINT="${OAUTH_ENDPOINT:-}"
TEST_USER_ID="${TEST_USER_ID:-e2e-test-user}"

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --runtime-arn) RUNTIME_ARN="$2"; shift 2 ;;
    --oauth-endpoint) OAUTH_ENDPOINT="$2"; shift 2 ;;
    --user-id) TEST_USER_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$OAUTH_ENDPOINT" ]; then
  OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreOAuth --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
fi

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  \033[32m✓ $1\033[0m"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[31m✗ $1\033[0m"; FAIL=$((FAIL+1)); }
skip() { echo -e "  \033[33m⊘ $1\033[0m"; SKIP=$((SKIP+1)); }

echo ""
echo "=== Lark MCP on AgentCore - 端到端测试 ==="
echo "  区域:    ${REGION}"
echo "  OAuth:   ${OAUTH_ENDPOINT:-<未设置>}"
echo "  Runtime: ${RUNTIME_ARN:-<未设置>}"
echo ""

# 测试 1: OAuth 流程
echo "── OAuth 流程 ──"
if [ -n "$OAUTH_ENDPOINT" ]; then
  ENC_USER=$(urlencode "$TEST_USER_ID")

  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/authorize?user_id=${ENC_USER}")
  if [ "$HTTP" = "302" ]; then pass "/authorize → 302 重定向"; else fail "/authorize → HTTP ${HTTP} (期望 302)"; fi

  REDIRECT=$(curl -s -o /dev/null -w "%{redirect_url}" "${OAUTH_ENDPOINT}/authorize?user_id=${ENC_USER}")
  if echo "$REDIRECT" | grep -q "state="; then pass "/authorize 包含 HMAC state"; else fail "/authorize 缺少 state"; fi

  TAMPER=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/callback?code=fake&state=dGFtcGVyZWQ6MTIzOmZha2U")
  if [ "$TAMPER" = "403" ]; then pass "/callback 拒绝篡改的 state"; else fail "/callback → HTTP ${TAMPER} (期望 403)"; fi

  TOKEN_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/token?user_id=test")
  if [ "$TOKEN_HTTP" = "405" ]; then pass "/token GET 返回 405 Method Not Allowed"; else fail "/token → HTTP ${TOKEN_HTTP} (期望 405)"; fi

  # MCP middleware should reject unauthenticated POSTs with 401.
  MCP_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "${OAUTH_ENDPOINT}/mcp")
  if [ "$MCP_HTTP" = "401" ]; then pass "/mcp 未授权请求 → 401"; else fail "/mcp → HTTP ${MCP_HTTP} (期望 401)"; fi

  # /mcp with malformed bearer should also 401.
  MCP_BAD=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer not-a-real-token" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "${OAUTH_ENDPOINT}/mcp")
  if [ "$MCP_BAD" = "401" ]; then pass "/mcp 无效 token → 401"; else fail "/mcp invalid token → HTTP ${MCP_BAD} (期望 401)"; fi
else
  skip "OAuth 端点未配置"
fi

# 测试 2: AgentCore Runtime
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

  if [ "$INIT_RESULT" = "OK" ]; then pass "MCP initialize 调用成功"; else fail "MCP initialize: ${INIT_RESULT}"; fi

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

  if [ "${TOOLS_RESULT:-0}" -gt "0" ]; then pass "tools/list 返回 ${TOOLS_RESULT} 个工具"; else fail "tools/list 返回 0 个工具"; fi

  TOKEN_TEST=$(python3 -c "
import boto3, json, urllib.parse, urllib.request
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
sm = boto3.client('secretsmanager', region_name='${REGION}')
try:
    secret = json.loads(sm.get_secret_value(SecretId='lark-mcp-on-agentcore/users/${TEST_USER_ID}')['SecretString'])
    uat = secret['access_token']
except:
    print('NO_TOKEN')
    exit(0)
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
url = f'https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/{urllib.parse.quote(\"${RUNTIME_ARN}\", safe=\"\")}/invocations'
body = json.dumps({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'lark_im_chat_list','arguments':{}}})
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
    USER_OK) pass "使用用户 Token 调用工具成功" ;;
    NO_TOKEN) skip "${TEST_USER_ID} 的 Token 不存在 (需先授权)" ;;
    *) fail "用户 Token 调用: ${TOKEN_TEST}" ;;
  esac
else
  skip "Runtime ARN 未配置"
fi

# 测试 3: Token 存储
echo ""
echo "── Token 存储 ──"
SM_TEST=$(aws secretsmanager list-secrets --region $REGION --filters "Key=name,Values=lark-mcp-on-agentcore/users" --query 'SecretList | length(@)' --output text 2>/dev/null || echo "0")
if [ "${SM_TEST:-0}" -gt "0" ]; then pass "Secrets Manager 存储了 ${SM_TEST} 个用户 Token"; else skip "暂无用户 Token"; fi

# 测试 4: EventBridge 刷新规则
echo ""
echo "── Token 刷新 ──"
EB_RULE=$(aws events list-rules --name-prefix LarkMcpOnAgentCoreOAuth --region $REGION --query 'Rules[0].Name' --output text 2>/dev/null || echo "")
if [ -z "$EB_RULE" ] || [ "$EB_RULE" = "None" ]; then EB_STATE="未找到"; else
EB_STATE=$(aws events describe-rule --name "$EB_RULE" --region $REGION --query 'State' --output text 2>/dev/null || echo "未找到"); fi
if [ "$EB_STATE" = "ENABLED" ]; then pass "EventBridge 刷新规则: 已启用"; else skip "EventBridge 规则: ${EB_STATE}"; fi

# 汇总
echo ""
echo "── WAF ──"
WAF_ARN=$(aws cloudformation describe-stacks --stack-name LarkMcpOnAgentCoreWaf --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`WebAclArn`].OutputValue' --output text 2>/dev/null || echo "")
if [ -n "$WAF_ARN" ] && [ "$WAF_ARN" != "None" ]; then
  pass "WAF WebACL 存在 (us-east-1)"
else
  skip "WAF WebACL 未找到"
fi

echo ""
echo "═══════════════════════════════════"
echo "  通过: ${PASS}  失败: ${FAIL}  跳过: ${SKIP}"
echo "═══════════════════════════════════"
echo ""

if [ $FAIL -gt 0 ]; then exit 1; fi
