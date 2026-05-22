FROM node:20-bookworm-slim

ARG LARK_CLI_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Install lark-cli
RUN npx @larksuite/cli@${LARK_CLI_VERSION} install 2>/dev/null || npm install -g @larksuite/cli@${LARK_CLI_VERSION}

# Install skills (required by lark-cli)
RUN npx skills add larksuite/cli -y -g 2>/dev/null || true

COPY generate-tools.js /app/generate-tools.js
COPY shortcut-scopes.json /app/shortcut-scopes.json
COPY server.js /app/server.js
COPY tier1.json /app/tier1.json

# Generate tool catalog at build time
RUN LARKSUITE_CLI_APP_ID=build LARKSUITE_CLI_APP_SECRET=build LARKSUITE_CLI_BRAND=feishu \
    node /app/generate-tools.js

USER node
EXPOSE 8000

ENTRYPOINT ["node", "/app/server.js"]
