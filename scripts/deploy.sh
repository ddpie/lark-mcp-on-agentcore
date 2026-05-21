#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Interactive deployment for lark-mcp-on-agentcore
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${GREEN}=== $1 ===${NC}\n"; }
info() { echo -e "${CYAN}  $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }
ask()  { read -rp "  $1: " "$2"; }

# Cleanup trap
cleanup() {
  if [ "${DEPLOY_STARTED:-false}" = "true" ]; then
    echo ""
    warn "部署中断。已创建的资源可通过以下方式清理:"
    info "  cd infra && npx cdk destroy --all"
    info "  或重新运行此脚本完成部署"
  fi
}
trap cleanup EXIT

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Lark MCP on AgentCore - Deploy         ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Prerequisites check
step "Check Environment / 检查环境"
DEPS_OK=true
for cmd in node docker aws python3; do
  if command -v $cmd &>/dev/null; then
    printf "  %-10s ✓\n" "$cmd"
  else
    err "Missing: ${cmd}"
    DEPS_OK=false
  fi
done

# Check Docker daemon
if command -v docker &>/dev/null && ! docker info &>/dev/null; then
  err "Docker daemon is not running. Please start Docker first."
  DEPS_OK=false
fi

# Check boto3
if ! python3 -c "import boto3" &>/dev/null; then
  err "Missing: python3 boto3 (pip3 install boto3)"
  DEPS_OK=false
fi

if [ "$DEPS_OK" = "false" ]; then
  echo ""
  warn "请先运行 install.sh 安装依赖:"
  info "bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)"
  exit 1
fi

# AWS credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  warn "AWS credentials not configured / AWS 凭证未配置"
  echo ""
  echo "  1) aws configure        (Access Key)"
  echo "  2) aws sso login        (SSO)"
  echo "  3) Retry / 重试          (already set via env)"
  echo ""
  read -rp "  Select / 选择 [1]: " AWS_CHOICE
  case "${AWS_CHOICE:-1}" in
    1) aws configure ;;
    2) aws sso login ;;
    3) ;;
  esac
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  if [ -z "$ACCOUNT_ID" ]; then
    err "Cannot authenticate with AWS. Please fix credentials and retry."
    exit 1
  fi
fi
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
info "AWS Account: ${ACCOUNT_ID}"
info "Region: ${REGION}"

# Feishu app credentials
step "Feishu App Configuration / 配置飞书应用"
echo "  需要飞书开放平台的应用凭证 (App ID + App Secret)"
echo "  Feishu Open Platform: https://open.feishu.cn/app"
echo ""

if [ -n "${FEISHU_APP_ID:-}" ]; then
  APP_ID="$FEISHU_APP_ID"
  info "App ID (env): ${APP_ID}"
else
  ask "Feishu App ID (e.g. cli_xxx)" APP_ID
fi

if [ -z "$APP_ID" ]; then
  err "App ID cannot be empty."
  exit 1
fi

if [ -n "${FEISHU_APP_SECRET:-}" ]; then
  APP_SECRET="$FEISHU_APP_SECRET"
  info "App Secret (env): ***"
else
  read -rsp "  Feishu App Secret: " APP_SECRET
  echo ""
fi

if [ -z "$APP_SECRET" ]; then
  err "App Secret cannot be empty."
  exit 1
fi

# lark-mcp version
echo ""
read -rp "  lark-mcp version [0.5.1]: " LARK_MCP_VERSION
LARK_MCP_VERSION="${LARK_MCP_VERSION:-0.5.1}"

# Region selection
echo ""
echo "  Select deploy region / 选择部署区域:"
echo ""
echo "    ── Americas ──"
echo "    1) us-west-2        Oregon (recommended)"
echo "    2) us-east-1        Virginia"
echo "    ── Asia Pacific ──"
echo "    3) ap-southeast-1   Singapore"
echo "    4) ap-northeast-1   Tokyo"
echo "    5) ap-southeast-2   Sydney"
echo "    6) ap-south-1       Mumbai"
echo "    ── Europe / Middle East ──"
echo "    7) eu-west-1        Ireland"
echo "    8) eu-central-1     Frankfurt"
echo "    9) me-central-1     UAE"
echo "    ──"
echo "    0) Custom / 手动输入"
echo ""
read -rp "  Select [1]: " REGION_CHOICE
case "${REGION_CHOICE:-1}" in
  1) REGION="us-west-2" ;;
  2) REGION="us-east-1" ;;
  3) REGION="ap-southeast-1" ;;
  4) REGION="ap-northeast-1" ;;
  5) REGION="ap-southeast-2" ;;
  6) REGION="ap-south-1" ;;
  7) REGION="eu-west-1" ;;
  8) REGION="eu-central-1" ;;
  9) REGION="me-central-1" ;;
  0) ask "Region (e.g. ca-central-1)" REGION ;;
  *) REGION="us-west-2" ;;
esac

# CDK bootstrap check
step "CDK Bootstrap"
BOOTSTRAP_CHECK=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$BOOTSTRAP_CHECK" = "NOT_FOUND" ]; then
  info "Region ${REGION} not bootstrapped."
  read -rp "  Run cdk bootstrap now? (Y/n) " BS_CONFIRM
  if [[ ! "${BS_CONFIRM:-y}" =~ ^[nN] ]]; then
    cd "${PROJECT_DIR}/infra"
    npm install --silent 2>/dev/null
    AWS_REGION="$REGION" npx cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}"
    cd "${PROJECT_DIR}"
  else
    err "CDK bootstrap required. Run: npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}"
    exit 1
  fi
else
  info "CDK Bootstrap: ✓"
fi

# Confirm
step "Confirm / 确认"
info "App ID:       ${APP_ID}"
info "lark-mcp:     v${LARK_MCP_VERSION}"
info "Region:       ${REGION}"
info "Account:      ${ACCOUNT_ID}"
echo ""
read -rp "  Start deploy? / 开始部署? (Y/n) " CONFIRM
if [[ "${CONFIRM:-y}" =~ ^[nN] ]]; then
  echo "  Cancelled."
  exit 0
fi

DEPLOY_STARTED=true

# Write context file (avoids secrets in command line / process list)
cat > "${PROJECT_DIR}/infra/cdk.context.json" << CTXEOF
{
  "feishuAppId": "${APP_ID}",
  "feishuAppSecret": "${APP_SECRET}",
  "runtimeArn": "",
  "larkMcpVersion": "${LARK_MCP_VERSION}"
}
CTXEOF
chmod 600 "${PROJECT_DIR}/infra/cdk.context.json"

# Step 1: CDK deploy
step "Step 1/4: CDK Deploy"
info "Building Docker image + deploying infrastructure..."
cd "${PROJECT_DIR}/infra"
npm install --silent 2>/dev/null
AWS_REGION="$REGION" npx cdk deploy --all --require-approval never 2>&1 | grep -E "✅|Outputs|Error|failed" || true

# Extract outputs
IMAGE_URI=$(aws cloudformation describe-stacks --stack-name LarkMcpRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ImageUri`].OutputValue' --output text 2>/dev/null || echo "")
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name LarkMcpRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RuntimeRoleArn`].OutputValue' --output text 2>/dev/null || echo "")
OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
REDIRECT_URL=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FeishuRedirectUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -z "$IMAGE_URI" ] || [ -z "$ROLE_ARN" ]; then
  err "CDK deploy failed. Check output above."
  exit 1
fi
info "Image: ${IMAGE_URI}"
info "OAuth: ${OAUTH_ENDPOINT}"

# Step 2: AgentCore Runtime
step "Step 2/4: AgentCore Runtime"
RUNTIME_ID=$(python3 << PYEOF
import boto3, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try:
    resp = c.create_agent_runtime(
        agentRuntimeName='larkmcp',
        description='Lark MCP Server v${LARK_MCP_VERSION}',
        roleArn='${ROLE_ARN}',
        agentRuntimeArtifact={'containerConfiguration': {'containerUri': '${IMAGE_URI}'}},
        networkConfiguration={'networkMode': 'PUBLIC'},
        protocolConfiguration={'serverProtocol': 'MCP'},
        requestHeaderConfiguration={'requestHeaderAllowlist': ['X-User-Access-Token', 'X-Runtime-User-Id']},
        environmentVariables={
            'APP_ID': '${APP_ID}',
            'APP_SECRET_ID': 'lark-mcp/feishu-app',
            'UAT_PLACEHOLDER': 'suppress_auth_handler',
            'SECRET_PREFIX': 'lark-mcp/users',
            'AUTHORIZE_BASE': '${OAUTH_ENDPOINT}',
        },
    )
    print(resp['agentRuntimeId'])
except Exception as e:
    if 'Conflict' in str(e):
        runtimes = c.list_agent_runtimes()
        for r in runtimes.get('agentRuntimeSummaries', []):
            if 'larkmcp' in r.get('agentRuntimeName', ''):
                print(r['agentRuntimeId'])
                sys.exit(0)
    print(f'ERROR:{e}', file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [ -z "$RUNTIME_ID" ] || [[ "$RUNTIME_ID" == ERROR* ]]; then
  err "Failed to create AgentCore Runtime."
  exit 1
fi
info "Runtime: ${RUNTIME_ID}"

info "Waiting for Runtime..."
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
for i in range(60):
    r = c.get_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
    s = r['status']
    if s == 'READY': print('  Ready ✓'); sys.exit(0)
    if s in ('FAILED','CREATE_FAILED'): print(f'  Failed: {r.get(\"failureReason\",\"?\")}', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  Timeout waiting for Runtime', file=sys.stderr); sys.exit(1)
"

# Step 3: Runtime Endpoint
step "Step 3/4: Runtime Endpoint"
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try: c.create_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', name='ep', agentRuntimeVersion='1')
except Exception as e:
    if 'Conflict' not in str(e): print(f'  Warning: {e}', file=sys.stderr)
for i in range(30):
    r = c.get_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep')
    if r['status'] == 'READY': print('  Endpoint Ready ✓'); sys.exit(0)
    if r['status'] == 'FAILED': print('  Endpoint failed', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  Timeout', file=sys.stderr); sys.exit(1)
"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"

# Step 4: Update Middleware
step "Step 4/4: Configure Middleware"
MIDDLEWARE_FN=$(aws cloudformation describe-stack-resources --stack-name LarkMcpMiddleware --region $REGION \
  --query 'StackResources[?ResourceType==`AWS::Lambda::Function`].PhysicalResourceId' --output text 2>/dev/null || echo "")

if [ -n "$MIDDLEWARE_FN" ]; then
  aws lambda update-function-configuration \
    --function-name "$MIDDLEWARE_FN" \
    --environment "Variables={RUNTIME_ARN=${RUNTIME_ARN},SECRET_PREFIX=lark-mcp/users,AUTHORIZE_BASE=${OAUTH_ENDPOINT},AWS_REGION=${REGION}}" \
    --region $REGION >/dev/null 2>&1
  info "Middleware configured ✓"
else
  warn "Middleware Lambda not found. Deploy LarkMcpMiddleware stack with runtimeArn context."
fi

# Update cdk.context.json with real ARN
sed -i "s|\"runtimeArn\": \"\"|\"runtimeArn\": \"${RUNTIME_ARN}\"|" "${PROJECT_DIR}/infra/cdk.context.json"

# Get MCP endpoint
MCP_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpMiddleware --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`McpEndpoint`].OutputValue' --output text 2>/dev/null || echo "N/A")

# Verification
step "Verify / 验证"
info "Testing OAuth..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/authorize?user_id=deploy-verify" 2>/dev/null || echo "000")
[ "$HTTP" = "302" ] && info "OAuth /authorize: ✓" || warn "OAuth /authorize: HTTP ${HTTP}"

info "Testing Runtime..."
python3 -c "
import boto3, json, sys
c = boto3.client('bedrock-agentcore', region_name='${REGION}', config=boto3.session.Config(read_timeout=30))
try:
    resp = c.invoke_agent_runtime(agentRuntimeArn='${RUNTIME_ARN}', contentType='application/json', accept='application/json, text/event-stream',
        payload=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'verify','version':'1'}}}))
    body = resp['response'].read().decode()
    if 'serverInfo' in body: print('  Runtime MCP: ✓')
    else: print('  Runtime responded but unexpected format')
except Exception as e:
    print(f'  Runtime: cold starting (retry in 30s)')
" 2>&1

DEPLOY_STARTED=false

# Done
echo ""
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Deploy Complete! ✓              ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
info "MCP Endpoint:  ${MCP_ENDPOINT}"
info "OAuth:         ${OAUTH_ENDPOINT}"
info "Runtime ARN:   ${RUNTIME_ARN}"
echo ""
echo -e "${YELLOW}  ⚠ Required: Add redirect URL to Feishu app:${NC}"
echo "    ${REDIRECT_URL}"
echo ""
echo "  Feishu app settings: https://open.feishu.cn/app/${APP_ID}/security"
echo ""
echo -e "  ${CYAN}User flow:${NC}"
echo "    1. Authorize: ${OAUTH_ENDPOINT}/authorize?user_id=<uid>"
echo "    2. Use MCP:   POST ${MCP_ENDPOINT} (with Cognito JWT)"
echo ""
echo -e "  ${CYAN}Teardown:${NC}"
echo "    cd infra && npx cdk destroy --all"
echo ""
echo -e "  ${CYAN}Run tests:${NC}"
echo "    RUNTIME_ARN=${RUNTIME_ARN} OAUTH_ENDPOINT=${OAUTH_ENDPOINT} ./scripts/test-e2e.sh"
