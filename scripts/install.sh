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
  echo "    /opt/homebrew/bin/bash ./scripts/install.sh" >&2
  echo "" >&2
  exit 1
fi

# 一键安装: curl -fsSL <url>/install.sh | bash

REPO="https://github.com/ddpie/lark-mcp-on-agentcore.git"
DIR="lark-mcp-on-agentcore"

# Language selection (only ask if not already set)
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
  L[title]="Lark MCP on AgentCore - 安装"
  L[checking_deps]="检查依赖..."
  L[missing_install]="缺少 %s，是否自动安装? (Y/n)"
  L[skipped]="跳过。请手动安装 %s 后重试。"
  L[install_failed]="安装失败，请手动安装 %s。"
  L[installing_node]="安装 Node.js 20..."
  L[installing_docker]="安装 Docker..."
  L[installing_aws]="安装 AWS CLI..."
  L[installing_cdk]="安装 AWS CDK..."
  L[start_docker]="请启动 Docker Desktop"
  L[missing_boto3]="缺少 python3 boto3，是否安装? (Y/n)"
  L[all_ready]="所有依赖就绪。"
  L[dir_exists]="目录已存在，更新中..."
  L[cloning]="克隆代码..."
  L[npm_deps]="安装 npm 依赖..."
  L[done]="安装完成。"
  L[start_deploy]="现在开始部署? (Y/n)"
  L[deploy_later]="稍后部署: cd %s && ./scripts/deploy.sh"
else
  L[title]="Lark MCP on AgentCore - Install"
  L[checking_deps]="Checking dependencies..."
  L[missing_install]="Missing %s, install automatically? (Y/n)"
  L[skipped]="Skipped. Please install %s manually."
  L[install_failed]="Install failed. Please install %s manually."
  L[installing_node]="Installing Node.js 20..."
  L[installing_docker]="Installing Docker..."
  L[installing_aws]="Installing AWS CLI..."
  L[installing_cdk]="Installing AWS CDK..."
  L[start_docker]="Please start Docker Desktop"
  L[missing_boto3]="Missing python3 boto3, install? (Y/n)"
  L[all_ready]="All dependencies ready."
  L[dir_exists]="Directory exists, updating..."
  L[cloning]="Cloning repository..."
  L[npm_deps]="Installing npm dependencies..."
  L[done]="Installation complete."
  L[start_deploy]="Start deployment now? (Y/n)"
  L[deploy_later]="Deploy later: cd %s && ./scripts/deploy.sh"
fi

t() { printf "${L[$1]}" "${@:2}"; }

echo ""
echo "  ╔══════════════════════════════════════════╗"
printf "  ║   %-39s║\n" "${L[title]}"
echo "  ╚══════════════════════════════════════════╝"
echo ""

OS="$(uname -s)"
ARCH="$(uname -m)"
PKG=""
if command -v apt-get &>/dev/null; then PKG="apt"
elif command -v yum &>/dev/null; then PKG="yum"
elif command -v brew &>/dev/null; then PKG="brew"
fi

install_pkg() {
  local cmd="$1"
  echo ""
  read -rp "  $(t missing_install "$cmd") " ans
  if [[ "${ans:-y}" =~ ^[nN] ]]; then
    echo "  $(t skipped "$cmd")"
    exit 1
  fi

  case "$cmd" in
    git)
      case $PKG in
        apt) sudo apt-get update -qq && sudo apt-get install -y git ;;
        yum) sudo yum install -y git ;;
        brew) brew install git ;;
      esac ;;
    node|npm)
      echo "  ${L[installing_node]}"
      if command -v fnm &>/dev/null; then fnm install 20 && fnm use 20
      elif command -v nvm &>/dev/null; then nvm install 20
      else
        curl -fsSL https://fnm.vercel.app/install | bash
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env)"
        fnm install 20 && fnm use 20
      fi ;;
    docker)
      echo "  ${L[installing_docker]}"
      case $PKG in
        apt) curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker "$USER" ;;
        yum) sudo yum install -y docker && sudo systemctl start docker && sudo usermod -aG docker "$USER" ;;
        brew) brew install --cask docker && echo "  ${L[start_docker]}" ;;
      esac ;;
    aws)
      echo "  ${L[installing_aws]}"
      case $OS in
        Linux) curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip && unzip -qo /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install ;;
        Darwin) curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg && sudo installer -pkg /tmp/AWSCLIV2.pkg -target / ;;
      esac ;;
    python3)
      case $PKG in
        apt) sudo apt-get update -qq && sudo apt-get install -y python3 ;;
        yum) sudo yum install -y python3 ;;
        brew) brew install python@3 ;;
      esac ;;
    cdk)
      echo "  ${L[installing_cdk]}"
      npm install -g aws-cdk ;;
  esac

  if ! command -v "$cmd" &>/dev/null && [ "$cmd" != "cdk" ]; then
    echo "  $(t install_failed "$cmd")"
    exit 1
  fi
}

echo "  ${L[checking_deps]}"
echo ""
for cmd in git node docker aws python3; do
  if command -v $cmd &>/dev/null; then
    printf "  %-10s ✓\n" "$cmd"
  else
    install_pkg "$cmd"
  fi
done

if ! command -v npm &>/dev/null; then install_pkg "node"; fi

if ! command -v cdk &>/dev/null; then
  if ! npx cdk --version &>/dev/null 2>&1; then
    install_pkg "cdk"
  fi
fi
printf "  %-10s ✓\n" "cdk"

if ! python3 -c "import boto3" &>/dev/null; then
  echo ""
  read -rp "  ${L[missing_boto3]} " ans
  if [[ ! "${ans:-y}" =~ ^[nN] ]]; then
    pip3 install boto3 --quiet
  fi
fi
printf "  %-10s ✓\n" "boto3"

echo ""
echo "  ${L[all_ready]}"

INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$INSTALL_SCRIPT_DIR")"

if [ -f "${PROJECT_ROOT}/scripts/deploy.sh" ] && [ -d "${PROJECT_ROOT}/infra" ]; then
  echo ""
  echo "  ${L[dir_exists]}"
  cd "$PROJECT_ROOT"
else
  echo ""
  if [ -d "$DIR" ]; then
    echo "  ${L[dir_exists]}"
    cd "$DIR" && git fetch origin && git reset --hard origin/main
  else
    echo "  ${L[cloning]}"
    git clone --depth 1 "$REPO" "$DIR"
    cd "$DIR"
  fi
fi

echo "  ${L[npm_deps]}"
npm install --silent 2>/dev/null
( cd infra && npm install --silent 2>/dev/null )
( cd docker && npm install --omit=dev --silent --no-audit --no-fund 2>/dev/null )

echo ""
echo "  ${L[done]}"
echo ""
read -rp "  ${L[start_deploy]} " START
if [[ "${START:-y}" =~ ^[nN] ]]; then
  echo ""
  echo "  $(t deploy_later "$(pwd)")"
  exit 0
fi

exec ./scripts/deploy.sh
