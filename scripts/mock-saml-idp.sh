#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Mock SAML IdP for local testing of Cognito SAML federation.
#
# Simulates Feilian as a SAML 2.0 IdP, posting assertions to Cognito's ACS.
#
# Usage:
#   ./scripts/mock-saml-idp.sh <cognito-user-pool-id> [region]
#
# Prerequisites:
#   npm install -g saml-idp
#
# The IdP starts on http://localhost:7000
# Metadata at http://localhost:7000/metadata (upload to Cognito)
# When Cognito redirects here, you can edit assertion attributes before posting.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
SAML_DIR="${PROJECT_DIR}/test/saml"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <cognito-user-pool-id> [region]"
  echo ""
  echo "Example: $0 us-west-2_AbCdEfGhI us-west-2"
  echo ""
  echo "Steps:"
  echo "  1. Deploy CDK:  cd infra && npx cdk deploy LarkMcpCognito"
  echo "  2. Start this script with the UserPoolId from stack output"
  echo "  3. Upload http://localhost:7000/metadata as Cognito SAML IdP metadata"
  echo "  4. Visit Cognito Hosted UI to trigger SP-initiated login"
  exit 1
fi

USER_POOL_ID="$1"
REGION="${2:-us-west-2}"

# Cognito SAML endpoints
ACS_URL="https://lark-mcp-${USER_POOL_ID##*_}.auth.${REGION}.amazoncognito.com/saml2/idpresponse"
AUDIENCE="urn:amazon:cognito:sp:${USER_POOL_ID}"

# Verify test certs exist
if [ ! -f "${SAML_DIR}/idp-private-key.pem" ]; then
  echo "ERROR: Missing test certificates. Generate them:"
  echo "  cd test/saml && openssl req -x509 -new -newkey rsa:2048 -nodes \\"
  echo "    -subj '/C=CN/ST=Beijing/L=Beijing/O=MockFeilian/CN=Mock Feilian IdP' \\"
  echo "    -keyout idp-private-key.pem -out idp-public-cert.pem -days 7300"
  exit 1
fi

echo "=== Mock SAML IdP (Feilian Simulator) ==="
echo ""
echo "Cognito ACS URL: ${ACS_URL}"
echo "Audience:        ${AUDIENCE}"
echo "IdP URL:         http://localhost:7000"
echo "Metadata:        http://localhost:7000/metadata"
echo ""

exec saml-idp \
  --acsUrl "${ACS_URL}" \
  --audience "${AUDIENCE}" \
  --host "127.0.0.1" \
  --port 7000 \
  --cert "$(cd "${SAML_DIR}" && pwd)/idp-public-cert.pem" \
  --key "$(cd "${SAML_DIR}" && pwd)/idp-private-key.pem" \
  --configFile "$(cd "${SAML_DIR}" && pwd)/config.js" \
  --issuer "urn:mock:feilian:idp"
