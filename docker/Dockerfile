FROM node:20-bookworm-slim

ARG LARK_MCP_VERSION=0.5.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsecret-1-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @larksuiteoapi/lark-mcp@${LARK_MCP_VERSION}
RUN npm install -g @aws-sdk/client-secrets-manager

COPY header-rewrite.js /app/header-rewrite.js

USER node
EXPOSE 8000

ENTRYPOINT ["node", "/app/header-rewrite.js"]
