#!/usr/bin/env bash
set -euo pipefail

# 一键安装: curl -fsSL <url>/install.sh | bash

REPO="https://github.com/ddpie/lark-mcp-on-agentcore.git"
DIR="lark-mcp-on-agentcore"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Lark MCP on AgentCore - 安装           ║"
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
  read -rp "  缺少 ${cmd}，是否自动安装? (Y/n) " ans
  if [[ "${ans:-y}" =~ ^[nN] ]]; then
    echo "  跳过。请手动安装 ${cmd} 后重试。"
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
      echo "  安装 Node.js 20..."
      if command -v fnm &>/dev/null; then fnm install 20 && fnm use 20
      elif command -v nvm &>/dev/null; then nvm install 20
      else
        curl -fsSL https://fnm.vercel.app/install | bash
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env)"
        fnm install 20 && fnm use 20
      fi ;;
    docker)
      echo "  安装 Docker..."
      case $PKG in
        apt) curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker "$USER" ;;
        yum) sudo yum install -y docker && sudo systemctl start docker && sudo usermod -aG docker "$USER" ;;
        brew) brew install --cask docker && echo "  请启动 Docker Desktop" ;;
      esac ;;
    aws)
      echo "  安装 AWS CLI..."
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
      echo "  安装 AWS CDK..."
      npm install -g aws-cdk ;;
  esac

  if ! command -v "$cmd" &>/dev/null && [ "$cmd" != "cdk" ]; then
    echo "  安装失败，请手动安装 ${cmd}。"
    exit 1
  fi
}

echo "  检查依赖..."
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
  read -rp "  缺少 python3 boto3，是否安装? (Y/n) " ans
  if [[ ! "${ans:-y}" =~ ^[nN] ]]; then
    pip3 install boto3 --quiet
  fi
fi
printf "  %-10s ✓\n" "boto3"

echo ""
echo "  所有依赖就绪。"

echo ""
if [ -d "$DIR" ]; then
  echo "  目录已存在，更新中..."
  cd "$DIR" && git fetch origin && git reset --hard origin/main
else
  echo "  克隆代码..."
  git clone --depth 1 "$REPO" "$DIR"
  cd "$DIR"
fi

echo "  安装 npm 依赖..."
npm install --silent 2>/dev/null
cd infra && npm install --silent 2>/dev/null && cd ..

echo ""
echo "  安装完成。"
echo ""
read -rp "  现在开始部署? (Y/n) " START
if [[ "${START:-y}" =~ ^[nN] ]]; then
  echo ""
  echo "  稍后部署: cd ${DIR} && ./scripts/deploy.sh"
  exit 0
fi

exec ./scripts/deploy.sh
