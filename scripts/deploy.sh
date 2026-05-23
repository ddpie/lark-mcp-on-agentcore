#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "" >&2
  echo "  bash 4+ required (current: ${BASH_VERSION})" >&2
  echo "" >&2
  echo "  Upgrade:" >&2
  echo "    macOS:  brew install bash && sudo bash -c 'echo /opt/homebrew/bin/bash >> /etc/shells'" >&2
  echo "    Linux:  sudo apt-get install -y bash  (or yum install bash)" >&2
  echo "" >&2
  echo "  Then re-run this script with the new bash:" >&2
  echo "    /opt/homebrew/bin/bash ./scripts/deploy.sh" >&2
  echo "" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Language selection (only ask if not already set by install.sh)
if [ -z "${LARK_LANG:-}" ]; then
  echo ""
  echo "  Select language / 选择语言:"
  echo ""
  echo "    1) 中文"
  echo "    2) English"
  echo ""
  read -rp "  [1]: " LANG_CHOICE
  case "${LANG_CHOICE:-1}" in
    2) export LARK_LANG="en" ;;
    *) export LARK_LANG="zh" ;;
  esac
fi

# --- i18n messages ---
declare -A L
if [ "$LARK_LANG" = "zh" ]; then
  L[title]="Lark MCP on AgentCore - 部署"
  L[title_done]="部署完成 ✓"
  L[check_env]="检查环境"
  L[docker_not_running]="Docker 未启动，请先启动 Docker。"
  L[run_install]="请先运行 install.sh 安装依赖:"
  L[aws_not_configured]="AWS 凭证未配置"
  L[aws_retry]="重试                  (已通过环境变量设置)"
  L[aws_fail]="无法认证 AWS，请检查凭证后重试。"
  L[configure_feishu]="配置飞书应用"
  L[feishu_creds_needed]="需要飞书开放平台的应用凭证 (App ID + App Secret)"
  L[feishu_platform]="飞书开放平台: https://open.feishu.cn/app"
  L[ask_app_id]="飞书 App ID (如 cli_xxx)"
  L[ask_app_secret]="飞书 App Secret: "
  L[app_id_empty]="App ID 不能为空。"
  L[app_secret_empty]="App Secret 不能为空。"
  L[confirm_creds]="确认? (Y=确认/n=取消/r=重新输入)"
  L[cancelled]="已取消。"
  L[re_enter]="重新输入..."
  L[custom_domain]="自定义域名 (可选，直接回车跳过): "
  L[ask_waf]="启用 CloudFront WAF (在 us-east-1 部署速率限制规则)? (y/N)"
  L[waf_enabled]="WAF: 启用 (us-east-1)"
  L[waf_disabled]="WAF: 禁用"
  L[select_region]="选择部署区域:"
  L[manual_input]="手动输入"
  L[ask_region]="区域 (如 ca-central-1)"
  L[not_bootstrapped]="区域 %s 尚未 Bootstrap。"
  L[run_bootstrap]="现在执行 cdk bootstrap? (Y/n)"
  L[confirm_deploy]="确认部署"
  L[start_deploy]="开始部署? (Y/n)"
  L[interrupted]="部署中断。可通过以下方式清理:"
  L[or_rerun]="或重新运行此脚本完成部署"
  L[clean_residuals]="清理残留资源"
  L[step_1]="第 1/4 步: CDK 部署"
  L[step_2]="第 2/4 步: AgentCore Runtime"
  L[step_3]="第 3/4 步: Runtime Endpoint"
  L[step_4]="第 4/4 步: 配置 Middleware"
  L[verify]="验证"
  L[creating_secrets]="创建/更新 Secrets Manager..."
  L[building]="构建 Docker 镜像 + 部署基础设施..."
  L[cdk_failed]="CDK 部署失败，最后 20 行日志:"
  L[cdk_check]="CDK 部署失败，请检查上方输出。"
  L[runtime_failed]="创建 AgentCore Runtime 失败。"
  L[waiting_runtime]="等待 Runtime 就绪..."
  L[testing_oauth]="测试 OAuth..."
  L[testing_runtime]="测试 Runtime..."
  L[deploy_info]="部署信息（请保存）"
  L[next_steps]="接下来请完成以下步骤:"
  L[step1_title]="步骤 1: 配置飞书应用重定向 URL"
  L[step1_open]="打开飞书应用安全设置:"
  L[step1_add]="添加重定向 URL:"
  L[step2_title]="步骤 2: 配置 Quick Desktop"
  L[step2_nav]="Quick Desktop: Settings → Capabilities → Browse Connections (跳转浏览器)"
  L[step2_browser]="浏览器中: Connectors → Create for your team → Model Context Protocol →"
  L[conn_info]="连接信息:"
  L[oauth_config]="OAuth 配置 (Create integration 后填写):"
  L[save_connect]="保存 → Connect → 浏览器授权飞书 → 自动连接"
  L[operations]="运维命令"
  L[op_list]="查看用户:    ./scripts/ops.sh list-users"
  L[op_revoke]="撤销授权:    ./scripts/ops.sh revoke <user_id>"
  L[op_status]="系统状态:    ./scripts/ops.sh status"
  L[op_destroy]="销毁资源:    ./scripts/teardown.sh"
  L[info_saved]="以上信息已保存到:"
else
  L[title]="Lark MCP on AgentCore - Deploy"
  L[title_done]="Deployment Complete ✓"
  L[check_env]="Check Environment"
  L[docker_not_running]="Docker is not running. Please start Docker first."
  L[run_install]="Please run install.sh first:"
  L[aws_not_configured]="AWS credentials not configured"
  L[aws_retry]="Retry                (already set via env)"
  L[aws_fail]="Cannot authenticate AWS. Please check credentials."
  L[configure_feishu]="Configure Feishu App"
  L[feishu_creds_needed]="Feishu Open Platform app credentials required (App ID + App Secret)"
  L[feishu_platform]="Feishu Open Platform: https://open.feishu.cn/app"
  L[ask_app_id]="Feishu App ID (e.g. cli_xxx)"
  L[ask_app_secret]="Feishu App Secret: "
  L[app_id_empty]="App ID cannot be empty."
  L[app_secret_empty]="App Secret cannot be empty."
  L[confirm_creds]="Confirm? (Y=yes/n=cancel/r=re-enter)"
  L[cancelled]="Cancelled."
  L[re_enter]="Re-entering..."
  L[custom_domain]="Custom domain (optional, press Enter to skip): "
  L[ask_waf]="Enable CloudFront WAF (rate-limit rules deployed in us-east-1)? (y/N)"
  L[waf_enabled]="WAF: enabled (us-east-1)"
  L[waf_disabled]="WAF: disabled"
  L[select_region]="Select deployment region:"
  L[manual_input]="Manual input"
  L[ask_region]="Region (e.g. ca-central-1)"
  L[not_bootstrapped]="Region %s not yet bootstrapped."
  L[run_bootstrap]="Run cdk bootstrap now? (Y/n)"
  L[confirm_deploy]="Confirm Deployment"
  L[start_deploy]="Start deployment? (Y/n)"
  L[interrupted]="Deployment interrupted. To clean up:"
  L[or_rerun]="Or re-run this script to resume."
  L[clean_residuals]="Clean Up Residuals"
  L[step_1]="Step 1/4: CDK Deploy"
  L[step_2]="Step 2/4: AgentCore Runtime"
  L[step_3]="Step 3/4: Runtime Endpoint"
  L[step_4]="Step 4/4: Configure Middleware"
  L[verify]="Verify"
  L[creating_secrets]="Creating/updating Secrets Manager..."
  L[building]="Building Docker image + deploying infrastructure..."
  L[cdk_failed]="CDK deploy failed. Last 20 lines:"
  L[cdk_check]="CDK deploy failed. Check output above."
  L[runtime_failed]="Failed to create AgentCore Runtime."
  L[waiting_runtime]="Waiting for Runtime to be ready..."
  L[testing_oauth]="Testing OAuth..."
  L[testing_runtime]="Testing Runtime..."
  L[deploy_info]="Deployment Info (please save)"
  L[next_steps]="Next steps:"
  L[step1_title]="Step 1: Configure Feishu App Redirect URL"
  L[step1_open]="Open Feishu app security settings:"
  L[step1_add]="Add redirect URL:"
  L[step2_title]="Step 2: Configure Quick Desktop"
  L[step2_nav]="Quick Desktop: Settings → Capabilities → Browse Connections (opens browser)"
  L[step2_browser]="In browser: Connectors → Create for your team → Model Context Protocol →"
  L[conn_info]="Connection info:"
  L[oauth_config]="OAuth config (fill after Create integration):"
  L[save_connect]="Save → Connect → Authorize in browser → Connected"
  L[operations]="Operations"
  L[op_list]="List users:     ./scripts/ops.sh list-users"
  L[op_revoke]="Revoke user:    ./scripts/ops.sh revoke <user_id>"
  L[op_status]="System status:  ./scripts/ops.sh status"
  L[op_destroy]="Destroy:        ./scripts/teardown.sh"
  L[info_saved]="Info saved to:"
fi

t() { printf "${L[$1]}" "${@:2}"; }
step() { echo -e "\n${GREEN}=== ${L[$1]} ===${NC}\n"; }
info() { echo -e "${CYAN}  $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }
ask()  { read -rp "  $1: " "$2"; }

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
  echo "  1) aws configure        (Access Key)"
  echo "  2) aws sso login        (SSO)"
  echo "  3) ${L[aws_retry]}"
  echo ""
  read -rp "  [1]: " AWS_CHOICE
  case "${AWS_CHOICE:-1}" in
    1) aws configure ;;
    2) aws sso login ;;
    3) ;;
  esac
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  if [ -z "$ACCOUNT_ID" ]; then
    err "${L[aws_fail]}"
    exit 1
  fi
fi
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
info "AWS Account: ${ACCOUNT_ID}"
info "Region: ${REGION}"

# 配置飞书应用
step configure_feishu
echo "  ${L[feishu_creds_needed]}"
echo "  ${L[feishu_platform]}"
echo ""

while true; do
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
  read -rp "  ${L[confirm_creds]} " CRED_CONFIRM
  case "${CRED_CONFIRM:-y}" in
    [nN]) echo "  ${L[cancelled]}"; exit 0 ;;
    [rR]) echo "  ${L[re_enter]}"; unset FEISHU_APP_ID FEISHU_APP_SECRET; continue ;;
    *) break ;;
  esac
done

# 自定义域名（可选）
echo ""
read -rp "  ${L[custom_domain]}" CUSTOM_DOMAIN
if [ -n "$CUSTOM_DOMAIN" ]; then
  if [[ ! "$CUSTOM_DOMAIN" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    err "Invalid domain: ${CUSTOM_DOMAIN}"
    exit 1
  fi
  info "Custom domain: ${CUSTOM_DOMAIN}"
fi

# WAF (default: off). Honor SKIP_WAF=1/0 env override; on non-interactive
# stdin (CI/cron), default to off without prompting.
if [ "${SKIP_WAF:-}" = "1" ]; then
  ENABLE_WAF=0
elif [ "${SKIP_WAF:-}" = "0" ]; then
  ENABLE_WAF=1
elif [ ! -t 0 ]; then
  ENABLE_WAF=0
else
  echo ""
  read -rp "  ${L[ask_waf]} " WAF_ANS
  if [[ "${WAF_ANS:-n}" =~ ^[yY] ]]; then ENABLE_WAF=1; else ENABLE_WAF=0; fi
fi
if [ "$ENABLE_WAF" = "1" ]; then info "${L[waf_enabled]}"; else info "${L[waf_disabled]}"; fi
export SKIP_WAF=$([ "$ENABLE_WAF" = "1" ] && echo 0 || echo 1)

# 选择区域
echo ""
echo "  ${L[select_region]}"
echo ""
echo "    ── Americas ──"
echo "    1) us-west-2        Oregon"
echo "    2) us-east-1        Virginia"
echo "    ── Asia Pacific ──"
echo "    3) ap-southeast-1   Singapore"
echo "    4) ap-northeast-1   Tokyo"
echo "    5) ap-southeast-2   Sydney"
echo "    6) ap-south-1       Mumbai"
echo "    ── Europe/Middle East ──"
echo "    7) eu-west-1        Ireland"
echo "    8) eu-central-1     Frankfurt"
echo "    9) me-central-1     UAE"
echo "    ──"
echo "    0) ${L[manual_input]}"
echo ""
read -rp "  [1]: " REGION_CHOICE
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
  0) ask "${L[ask_region]}" REGION ;;
  *) REGION="us-west-2" ;;
esac

# CDK Bootstrap (deploy region + us-east-1 for the CloudFront-scope WAF)
step step_1
ensure_bootstrap() {
  local target_region="$1"
  local check
  check=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region "$target_region" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [ "$check" = "NOT_FOUND" ]; then
    info "$(t not_bootstrapped "$target_region")"
    read -rp "  ${L[run_bootstrap]} " BS_CONFIRM
    if [[ ! "${BS_CONFIRM:-y}" =~ ^[nN] ]]; then
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
read -rp "  ${L[start_deploy]} " CONFIRM
if [[ "${CONFIRM:-y}" =~ ^[nN] ]]; then
  echo "  ${L[cancelled]}"
  exit 0
fi

DEPLOY_STARTED=true

# 清理残留资源
step clean_residuals
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

# CDK 部署
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
    STATE_SECRET="$STATE_SECRET_VAL" \
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
  "STATE_SECRET": os.environ["STATE_SECRET"],
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

# OAuth Client 信息
OAUTH_CLIENT_ID="lark-mcp-on-agentcore"
OAUTH_CLIENT_SECRET_VAL="${OAUTH_SECRET_VAL}"

# 保存部署信息
DEPLOY_INFO="${PROJECT_DIR}/deploy-output.md"
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
echo "  OAuth Client Secret:   ${OAUTH_CLIENT_SECRET_VAL:0:8}..."
echo "  Token URL:             ${OAUTH_ENDPOINT}/token"
echo "  Authorization URL:     ${OAUTH_ENDPOINT}/authorize"
echo "  Redirect URL:          ${REDIRECT_URL}"
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
