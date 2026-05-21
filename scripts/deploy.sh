#!/usr/bin/env bash
set -euo pipefail

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

cleanup() {
  if [ "${DEPLOY_STARTED:-false}" = "true" ]; then
    echo ""
    warn "部署中断。可通过以下方式清理:"
    info "  cd infra && npx cdk destroy --all"
    info "  或重新运行此脚本完成部署"
  fi
}
trap cleanup EXIT

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Lark MCP on AgentCore - 部署           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# 检查环境
step "检查环境"
DEPS_OK=true
for cmd in node docker aws python3; do
  if command -v $cmd &>/dev/null; then
    printf "  %-10s ✓\n" "$cmd"
  else
    err "缺少: ${cmd}"
    DEPS_OK=false
  fi
done

if command -v docker &>/dev/null && ! docker info &>/dev/null; then
  err "Docker 未启动，请先启动 Docker。"
  DEPS_OK=false
fi

if ! python3 -c "import boto3" &>/dev/null; then
  err "缺少: python3 boto3 (pip3 install boto3)"
  DEPS_OK=false
fi

if [ "$DEPS_OK" = "false" ]; then
  echo ""
  warn "请先运行 install.sh 安装依赖:"
  info "bash <(curl -fsSL https://raw.githubusercontent.com/ddpie/lark-mcp-on-agentcore/main/scripts/install.sh)"
  exit 1
fi

# AWS 凭证
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  warn "AWS 凭证未配置"
  echo ""
  echo "  1) aws configure        (Access Key)"
  echo "  2) aws sso login        (SSO)"
  echo "  3) 重试                  (已通过环境变量设置)"
  echo ""
  read -rp "  选择 [1]: " AWS_CHOICE
  case "${AWS_CHOICE:-1}" in
    1) aws configure ;;
    2) aws sso login ;;
    3) ;;
  esac
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  if [ -z "$ACCOUNT_ID" ]; then
    err "无法认证 AWS，请检查凭证后重试。"
    exit 1
  fi
fi
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
info "AWS Account: ${ACCOUNT_ID}"
info "Region: ${REGION}"

# 配置飞书应用
step "配置飞书应用"
echo "  需要飞书开放平台的应用凭证 (App ID + App Secret)"
echo "  飞书开放平台: https://open.feishu.cn/app"
echo ""

while true; do
  if [ -n "${FEISHU_APP_ID:-}" ]; then
    APP_ID="$FEISHU_APP_ID"
    info "App ID (环境变量): ${APP_ID}"
  else
    ask "飞书 App ID (如 cli_xxx)" APP_ID
  fi

  if [ -z "$APP_ID" ]; then
    err "App ID 不能为空。"
    continue
  fi

  if [ -n "${FEISHU_APP_SECRET:-}" ]; then
    APP_SECRET="$FEISHU_APP_SECRET"
    info "App Secret (环境变量): ***"
  else
    echo -n "  飞书 App Secret: "
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
    err "App Secret 不能为空。"
    continue
  fi

  echo ""
  info "App ID:     ${APP_ID}"
  info "App Secret: ${APP_SECRET:0:4}****"
  read -rp "  确认? (Y=确认/n=取消/r=重新输入) " CRED_CONFIRM
  case "${CRED_CONFIRM:-y}" in
    [nN]) echo "  已取消。"; exit 0 ;;
    [rR]) echo "  重新输入..."; unset FEISHU_APP_ID FEISHU_APP_SECRET; continue ;;
    *) break ;;
  esac
done


# 自定义域名（可选）
echo ""
read -rp "  自定义域名 (可选，直接回车跳过): " CUSTOM_DOMAIN
if [ -n "$CUSTOM_DOMAIN" ]; then
  info "自定义域名: ${CUSTOM_DOMAIN}"
fi

# 选择区域
echo ""
echo "  选择部署区域:"
echo ""
echo "    ── 美洲 ──"
echo "    1) us-west-2        俄勒冈"
echo "    2) us-east-1        弗吉尼亚"
echo "    ── 亚太 ──"
echo "    3) ap-southeast-1   新加坡"
echo "    4) ap-northeast-1   东京"
echo "    5) ap-southeast-2   悉尼"
echo "    6) ap-south-1       孟买"
echo "    ── 欧洲/中东 ──"
echo "    7) eu-west-1        爱尔兰"
echo "    8) eu-central-1     法兰克福"
echo "    9) me-central-1     阿联酋"
echo "    ──"
echo "    0) 手动输入"
echo ""
read -rp "  选择 [1]: " REGION_CHOICE
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
  0) ask "区域 (如 ca-central-1)" REGION ;;
  *) REGION="us-west-2" ;;
esac

# CDK Bootstrap
step "CDK Bootstrap"
BOOTSTRAP_CHECK=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$BOOTSTRAP_CHECK" = "NOT_FOUND" ]; then
  info "区域 ${REGION} 尚未 Bootstrap。"
  read -rp "  现在执行 cdk bootstrap? (Y/n) " BS_CONFIRM
  if [[ ! "${BS_CONFIRM:-y}" =~ ^[nN] ]]; then
    cd "${PROJECT_DIR}/infra"
    npm install --silent 2>/dev/null
    AWS_REGION="$REGION" npx cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}"
    cd "${PROJECT_DIR}"
  else
    err "需要先 Bootstrap。运行: npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}"
    exit 1
  fi
else
  info "CDK Bootstrap: ✓"
fi

# 确认
step "确认部署"
info "App ID:       ${APP_ID}"
info "Region:       ${REGION}"
info "Account:      ${ACCOUNT_ID}"
echo ""
read -rp "  开始部署? (Y/n) " CONFIRM
if [[ "${CONFIRM:-y}" =~ ^[nN] ]]; then
  echo "  已取消。"
  exit 0
fi

DEPLOY_STARTED=true

# 清理残留资源
step "清理残留资源"
for STACK_NAME in LarkMcpOAuth LarkMcpRuntime; do
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
    warn "Stack ${STACK_NAME} 状态为 ${STACK_STATUS}，正在删除..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
  fi
done

for SECRET_NAME in "lark-mcp/feishu-app"; do
  SECRET_STATUS=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" \
    --query 'DeletedDate' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$SECRET_STATUS" != "NOT_FOUND" ] && [ "$SECRET_STATUS" != "None" ]; then
    info "清理待删除 Secret: ${SECRET_NAME}"
    aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
      --force-delete-without-recovery 2>/dev/null || true
  elif [ "$SECRET_STATUS" = "None" ]; then
    OWNING_STACK=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region "$REGION" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$OWNING_STACK" = "NOT_FOUND" ]; then
      warn "发现孤立 Secret ${SECRET_NAME}，正在清理..."
      aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --region "$REGION" \
        --force-delete-without-recovery 2>/dev/null || true
    fi
  fi
done

SSM_EXISTS=$(aws ssm get-parameter --name "/lark-mcp/state-secret" --region "$REGION" \
  --query 'Parameter.Name' --output text 2>/dev/null || echo "NOT_FOUND")
OAUTH_STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$SSM_EXISTS" != "NOT_FOUND" ] && [ "$OAUTH_STACK_EXISTS" = "NOT_FOUND" ]; then
  info "清理孤立 SSM 参数: /lark-mcp/state-secret"
  aws ssm delete-parameter --name "/lark-mcp/state-secret" --region "$REGION" 2>/dev/null || true
fi

RUNTIME_STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name LarkMcpRuntime --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$RUNTIME_STACK_EXISTS" = "NOT_FOUND" ]; then
  if aws iam get-role --role-name LarkMcpAgentCoreRole &>/dev/null; then
    warn "清理孤立 IAM Role: LarkMcpAgentCoreRole"
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name LarkMcpAgentCoreRole \
      --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
      aws iam detach-role-policy --role-name LarkMcpAgentCoreRole --policy-arn "$POLICY_ARN" 2>/dev/null || true
    done
    aws iam delete-role --role-name LarkMcpAgentCoreRole 2>/dev/null || true
  fi
fi

info "清理完成 ✓"

# 第 1 步: CDK 部署
step "第 1/4 步: CDK 部署"

# Create/update Feishu app secret in Secrets Manager (outside CDK to avoid overwrite on redeploy)
info "创建/更新 Secrets Manager..."
SECRET_VALUE=$(printf '{"appId":"%s","appSecret":"%s"}' "$APP_ID" "$APP_SECRET")
if aws secretsmanager describe-secret --secret-id "lark-mcp/feishu-app" --region "$REGION" &>/dev/null; then
  aws secretsmanager put-secret-value --secret-id "lark-mcp/feishu-app" \
    --secret-string "$SECRET_VALUE" --region "$REGION" >/dev/null 2>&1
  info "Secret 已更新 ✓"
else
  aws secretsmanager create-secret --name "lark-mcp/feishu-app" \
    --secret-string "$SECRET_VALUE" --region "$REGION" >/dev/null 2>&1
  info "Secret 已创建 ✓"
fi

# Create state secret SSM parameter if not exists
if ! aws ssm get-parameter --name "/lark-mcp/state-secret" --region "$REGION" &>/dev/null; then
  STATE_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  aws ssm put-parameter --name "/lark-mcp/state-secret" --value "$STATE_SECRET_VAL" \
    --type SecureString --region "$REGION" >/dev/null 2>&1
  info "State secret 已创建 ✓"
else
  STATE_SECRET_VAL=$(aws ssm get-parameter --name "/lark-mcp/state-secret" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "State secret 已存在 ✓"
fi

# Create OAuth client secret if not exists
if ! aws ssm get-parameter --name "/lark-mcp/oauth-client-secret" --region "$REGION" &>/dev/null; then
  OAUTH_SECRET_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  aws ssm put-parameter --name "/lark-mcp/oauth-client-secret" --value "$OAUTH_SECRET_VAL" \
    --type SecureString --region "$REGION" >/dev/null 2>&1
  info "OAuth Client Secret 已创建 ✓"
else
  OAUTH_SECRET_VAL=$(aws ssm get-parameter --name "/lark-mcp/oauth-client-secret" --region "$REGION" --with-decryption --query 'Parameter.Value' --output text)
  info "OAuth Client Secret 已存在 ✓"
fi

info "构建 Docker 镜像 + 部署基础设施..."
cd "${PROJECT_DIR}"
npm install --silent 2>/dev/null
cd "${PROJECT_DIR}/infra"
npm install --silent 2>/dev/null
export FEISHU_APP_ID="$APP_ID"
export FEISHU_APP_SECRET="$APP_SECRET"
export CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-}"
if ! AWS_REGION="$REGION" npx cdk deploy LarkMcpRuntime LarkMcpOAuth --require-approval never 2>&1 | tee /tmp/cdk-deploy.log; then
  echo ""
  err "CDK 部署失败，最后 20 行日志:"
  tail -20 /tmp/cdk-deploy.log
  exit 1
fi
unset FEISHU_APP_SECRET

# 提取输出
IMAGE_URI=$(aws cloudformation describe-stacks --stack-name LarkMcpRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ImageUri`].OutputValue' --output text 2>/dev/null || echo "")
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name LarkMcpRuntime --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RuntimeRoleArn`].OutputValue' --output text 2>/dev/null || echo "")
OAUTH_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthEndpoint`].OutputValue' --output text 2>/dev/null || echo "")
REDIRECT_URL=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FeishuRedirectUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -z "$IMAGE_URI" ] || [ -z "$ROLE_ARN" ]; then
  err "CDK 部署失败，请检查上方输出。"
  exit 1
fi
info "Image: ${IMAGE_URI}"
info "OAuth: ${OAUTH_ENDPOINT}"

# 设置 OAuth Lambda 的 CALLBACK_URL
OAUTH_FN=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`OAuthFunctionName`].OutputValue' --output text 2>/dev/null || echo "")
STATE_SECRET_VAL=$(aws ssm get-parameter --name /lark-mcp/state-secret --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')
OAUTH_SECRET_VAL=$(aws ssm get-parameter --name /lark-mcp/oauth-client-secret --region $REGION --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo 'fallback')
if [ -n "$OAUTH_FN" ] && [ -n "$OAUTH_ENDPOINT" ]; then
  aws lambda update-function-configuration \
    --function-name "$OAUTH_FN" \
    --environment "Variables={CALLBACK_URL=${OAUTH_ENDPOINT}/callback,SECRET_PREFIX=lark-mcp/users,APP_SECRET_ID=lark-mcp/feishu-app,STATE_SECRET=${STATE_SECRET_VAL},OAUTH_CLIENT_ID=lark-mcp,OAUTH_CLIENT_SECRET=${OAUTH_SECRET_VAL}${CUSTOM_DOMAIN:+,ALLOWED_DOMAINS=${CUSTOM_DOMAIN}}}" \
    --region $REGION >/dev/null 2>&1
  info "OAuth Lambda CALLBACK_URL 已配置 ✓"
fi

# 第 2 步: AgentCore Runtime
step "第 2/4 步: AgentCore Runtime"
RUNTIME_ID=$(python3 << PYEOF
import boto3, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try:
    resp = c.create_agent_runtime(
        agentRuntimeName='larkmcp',
        description='Lark MCP Server (lark-cli)',
        roleArn='${ROLE_ARN}',
        agentRuntimeArtifact={'containerConfiguration': {'containerUri': '${IMAGE_URI}'}},
        networkConfiguration={'networkMode': 'PUBLIC'},
        protocolConfiguration={'serverProtocol': 'MCP'},
        requestHeaderConfiguration={'requestHeaderAllowlist': ['X-User-Access-Token', 'X-Runtime-User-Id']},
        environmentVariables={
            'APP_ID': '${APP_ID}',
            'APP_SECRET': '${APP_SECRET}',
            'LARKSUITE_CLI_BRAND': 'feishu',
        },
    )
    print(resp['agentRuntimeId'])
except Exception as e:
    if 'Conflict' in str(e):
        next_token = None
        while True:
            kwargs = {'nextToken': next_token} if next_token else {}
            runtimes = c.list_agent_runtimes(**kwargs)
            for r in runtimes.get('agentRuntimes', []):
                if r.get('agentRuntimeName') == 'larkmcp':
                    print(r['agentRuntimeId'])
                    sys.exit(0)
            next_token = runtimes.get('nextToken')
            if not next_token: break
    print(f'ERROR:{e}', file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [ -z "$RUNTIME_ID" ] || [[ "$RUNTIME_ID" == ERROR* ]]; then
  err "创建 AgentCore Runtime 失败。"
  exit 1
fi
info "Runtime: ${RUNTIME_ID}"

info "等待 Runtime 就绪..."
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
for i in range(60):
    r = c.get_agent_runtime(agentRuntimeId='${RUNTIME_ID}')
    s = r['status']
    if s == 'READY': print('  就绪 ✓'); sys.exit(0)
    if s in ('FAILED','CREATE_FAILED'): print(f'  失败: {r.get(\"failureReason\",\"?\")}', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  等待超时', file=sys.stderr); sys.exit(1)
"

# 第 3 步: Runtime Endpoint
step "第 3/4 步: Runtime Endpoint"
python3 -c "
import boto3, time, sys
c = boto3.client('bedrock-agentcore-control', region_name='${REGION}')
try: c.create_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', name='ep', agentRuntimeVersion='1')
except Exception as e:
    if 'Conflict' not in str(e): print(f'  警告: {e}', file=sys.stderr)
for i in range(30):
    r = c.get_agent_runtime_endpoint(agentRuntimeId='${RUNTIME_ID}', endpointName='ep')
    if r['status'] == 'READY': print('  Endpoint 就绪 ✓'); sys.exit(0)
    if r['status'] == 'FAILED': print('  Endpoint 创建失败', file=sys.stderr); sys.exit(1)
    time.sleep(5)
print('  等待超时', file=sys.stderr); sys.exit(1)
"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"

# 第 4 步: 配置 Middleware
step "第 4/4 步: 配置 Middleware"
# Middleware Lambda is now part of LarkMcpOAuth stack
MIDDLEWARE_FN=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`MiddlewareFunctionName`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$MIDDLEWARE_FN" ]; then
  aws lambda update-function-configuration \
    --function-name "$MIDDLEWARE_FN" \
    --environment "Variables={RUNTIME_ARN=${RUNTIME_ARN},SECRET_PREFIX=lark-mcp/users,AUTHORIZE_BASE=${OAUTH_ENDPOINT},DEPLOY_REGION=${REGION}}" \
    --region $REGION >/dev/null 2>&1
  info "Middleware 已配置 ✓"
else
  warn "未找到 Middleware Lambda，请检查 LarkMcpOAuth Stack。"
fi

# 获取 MCP endpoint (now from LarkMcpOAuth stack)
MCP_ENDPOINT=$(aws cloudformation describe-stacks --stack-name LarkMcpOAuth --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`McpEndpoint`].OutputValue' --output text 2>/dev/null || echo "N/A")

# 验证
step "验证"
info "测试 OAuth..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${OAUTH_ENDPOINT}/authorize?user_id=deploy-verify" 2>/dev/null || echo "000")
[ "$HTTP" = "302" ] && info "OAuth /authorize: ✓" || warn "OAuth /authorize: HTTP ${HTTP}"

info "测试 Runtime..."
python3 -c "
import boto3, json, sys
c = boto3.client('bedrock-agentcore', region_name='${REGION}', config=boto3.session.Config(read_timeout=30))
try:
    resp = c.invoke_agent_runtime(agentRuntimeArn='${RUNTIME_ARN}', contentType='application/json', accept='application/json, text/event-stream',
        payload=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'verify','version':'1'}}}))
    body = resp['response'].read().decode()
    if 'serverInfo' in body: print('  Runtime MCP: ✓')
    else: print('  Runtime 响应格式异常')
except Exception as e:
    print(f'  Runtime: 冷启动中 (30 秒后重试)')
" 2>&1

DEPLOY_STARTED=false

# 获取 OAuth Client 信息
OAUTH_CLIENT_ID="lark-mcp"
OAUTH_CLIENT_SECRET_VAL="${OAUTH_SECRET_VAL}"

# 保存部署信息到文件
DEPLOY_INFO="${PROJECT_DIR}/deploy-output.md"
cat > "$DEPLOY_INFO" << INFOEOF
# Lark MCP on AgentCore - 部署信息

> 部署时间: $(date '+%Y-%m-%d %H:%M:%S')
> 区域: ${REGION}
> 账户: ${ACCOUNT_ID}

## Quick Desktop 配置

Settings → Capabilities → Browse Connections → Connectors →
Create for your team → Model Context Protocol → No, create new

连接信息:
| 字段 | 值 |
|------|-----|
| Name | Feishu (Lark) |
| MCP server endpoint | ${MCP_ENDPOINT} |
| Connection type | public |

Create integration 后填写 OAuth:
| 字段 | 值 |
|------|-----|
| Client ID | ${OAUTH_CLIENT_ID} |
| Client Secret | ${OAUTH_CLIENT_SECRET_VAL} |
| Token URL | ${OAUTH_ENDPOINT}/token |
| Authorization URL | ${OAUTH_ENDPOINT}/authorize |

保存 → Connect → 浏览器授权飞书 → 自动连接。

## 飞书应用重定向 URL

打开飞书应用安全设置:
https://open.feishu.cn/app/${APP_ID}/safe

添加重定向 URL:
${REDIRECT_URL}

## 运维命令

\`\`\`bash
./scripts/ops.sh list-users       # 查看已授权用户
./scripts/ops.sh revoke <id>      # 撤销用户授权
./scripts/ops.sh status           # 系统概览

cd infra && npx cdk destroy --all # 销毁所有 AWS 资源
\`\`\`

## 运行测试

\`\`\`bash
RUNTIME_ARN=${RUNTIME_ARN} OAUTH_ENDPOINT=${OAUTH_ENDPOINT} ./scripts/test-e2e.sh
\`\`\`
INFOEOF

# 完成
echo ""
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║            部署完成 ✓                     ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  部署信息（请保存）${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  MCP Endpoint:          ${MCP_ENDPOINT}"
echo "  OAuth Client ID:       ${OAUTH_CLIENT_ID}"
echo "  OAuth Client Secret:   ${OAUTH_CLIENT_SECRET_VAL:0:8}..."
echo "  Token URL:             ${OAUTH_ENDPOINT}/token"
echo "  Authorization URL:     ${OAUTH_ENDPOINT}/authorize"
echo "  Redirect URL:          ${REDIRECT_URL}"
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  接下来请完成以下步骤:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}  步骤 1: 配置飞书应用重定向 URL${NC}"
echo ""
echo "    打开飞书应用安全设置:"
echo "    https://open.feishu.cn/app/${APP_ID}/safe"
echo ""
echo "    添加重定向 URL:"
echo "    ${REDIRECT_URL}"
echo ""
echo -e "${CYAN}  步骤 2: 配置 Quick Desktop${NC}"
echo ""
echo "    Quick Desktop: Settings → Capabilities → Browse Connections (跳转浏览器)"
echo "    浏览器中: Connectors → Create for your team → Model Context Protocol →"
echo "    No, create new"
echo ""
echo "    连接信息:"
echo "      Name:               Feishu (Lark)"
echo "      MCP server endpoint: ${MCP_ENDPOINT}"
echo "      Connection type:    public"
echo ""
echo "    OAuth 配置 (Create integration 后填写):"
echo "      Client ID:          ${OAUTH_CLIENT_ID}"
echo "      Client Secret:      ${OAUTH_CLIENT_SECRET_VAL}"
echo "      Token URL:          ${OAUTH_ENDPOINT}/token"
echo "      Authorization URL:  ${OAUTH_ENDPOINT}/authorize"
echo ""
echo "    保存 → Connect → 浏览器授权飞书 → 自动连接"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  运维命令${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  查看用户:    ./scripts/ops.sh list-users"
echo "  撤销授权:    ./scripts/ops.sh revoke <user_id>"
echo "  系统状态:    ./scripts/ops.sh status"
echo "  销毁资源:    cd infra && npx cdk destroy --all"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  以上信息已保存到: ${CYAN}${DEPLOY_INFO}${NC}"
echo ""
