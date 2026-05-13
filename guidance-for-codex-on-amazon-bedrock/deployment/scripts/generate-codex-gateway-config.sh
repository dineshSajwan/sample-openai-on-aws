#!/usr/bin/env bash
# Generate a developer bundle for the LiteLLM Gateway path.
# Writes install.sh / uninstall.sh / DEV-SETUP.md / config.toml fragment
# into the output directory for a single developer.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: generate-codex-gateway-config.sh [options]

Required:
  --gateway-url URL       Full gateway endpoint (e.g. https://gw.example.com/v1)

Optional:
  --key-mint-url URL      Self-service key endpoint (e.g. https://gw/sso/key/generate)
  --model ID              Default model alias (default: openai.gpt-5.4)
  --profile-name NAME     Codex profile name (default: codex-gateway)
  --outdir DIR            Output directory (default: ./codex-gateway-config)
USAGE
}

GATEWAY_URL=""
KEY_MINT_URL=""
MODEL="openai.gpt-5.4"
PROFILE_NAME="codex-gateway"
OUTDIR="./codex-gateway-config"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-url) GATEWAY_URL="$2"; shift 2 ;;
    --key-mint-url) KEY_MINT_URL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --profile-name) PROFILE_NAME="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$GATEWAY_URL" ]]; then
  echo "missing required flag: --gateway-url" >&2
  usage
  exit 2
fi

mkdir -p "$OUTDIR"

cat >"$OUTDIR/config.toml.fragment" <<TOML
# >>> codex-gateway managed: do not edit inside fences <<<
# Codex CLI configuration for LiteLLM Gateway
model = "$MODEL"
model_provider = "litellm-gateway"

[model_providers.litellm-gateway]
name = "LiteLLM Gateway"
type = "openai"
base_url = "$GATEWAY_URL"
api_key = "env:OPENAI_API_KEY"
# >>> end codex-gateway managed <<<
TOML

cat >"$OUTDIR/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cfg="$HOME/.codex/config.toml"
mkdir -p "$HOME/.codex"
touch "$cfg"

# Strip any prior managed block, then append.
awk '/# >>> end codex-gateway managed/{skip=0; next} /# >>> codex-gateway managed/{skip=1} !skip{print}' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"
# Ensure trailing newline so the next awk pass can match the fence on its own line.
[[ -s "$cfg" && $(tail -c1 "$cfg") != "" ]] && printf '\n' >>"$cfg"
cat "$here/config.toml.fragment" >>"$cfg"

echo "Wrote managed block to $cfg"
echo "Add OPENAI_API_KEY to your shell profile (see DEV-SETUP.md)."
INSTALL
chmod +x "$OUTDIR/install.sh"

cat >"$OUTDIR/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail
cfg="$HOME/.codex/config.toml"
[[ -f "$cfg" ]] || exit 0
awk '/# >>> end codex-gateway managed/{skip=0; next} /# >>> codex-gateway managed/{skip=1} !skip{print}' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"
echo "Removed managed block from $cfg"
UNINSTALL
chmod +x "$OUTDIR/uninstall.sh"

KEY_SECTION="Ask your platform team for a per-user key."
if [[ -n "$KEY_MINT_URL" ]]; then
  KEY_SECTION=$(cat <<MINT
Self-service via IdP SSO:

\`\`\`bash
open "$KEY_MINT_URL"
# Copy the sk-... key the page returns, then:
export OPENAI_API_KEY="sk-..."
\`\`\`
MINT
)
fi

cat >"$OUTDIR/DEV-SETUP.md" <<SETUP
# Codex on Bedrock — Developer Setup

Gateway: $GATEWAY_URL
Model:   $MODEL
Profile: $PROFILE_NAME

## Overview

Access Codex on Amazon Bedrock through your LiteLLM Gateway using two methods:

| Method | Tool | Use Case |
|--------|------|----------|
| **Method 1** | Direct API calls (curl/scripts) | Testing, CI/CD, simple integrations |
| **Method 2** | OpenAI Codex CLI | Interactive coding assistance |

Both methods go through the **same LiteLLM Gateway** for quotas, OIDC, and analytics.

---

## Setup

### 1. Get API Key

$KEY_SECTION

### 2. Install Configuration

\`\`\`bash
./install.sh
\`\`\`

This writes Codex CLI configuration to \`~/.codex/config.toml\` with the \`litellm-gateway\` provider.

---

## Method 1: Direct API Calls (curl / OpenAI SDK)

### Using curl

\`\`\`bash
# Set API key
export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"

# Test with curl
curl -X POST "$GATEWAY_URL/chat/completions" \\
  -H "Authorization: Bearer \$OPENAI_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "$MODEL",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'

# Expected response:
# {"id":"chatcmpl-...","choices":[{"message":{"content":"Hello! ..."}}]}
\`\`\`

### Using OpenAI Python SDK

\`\`\`bash
# Install SDK
pip install openai

# Create a script
cat > test_gateway.py <<'PYTHON'
from openai import OpenAI
import os

client = OpenAI(
    base_url="$GATEWAY_URL",
    api_key=os.environ["OPENAI_API_KEY"]
)

response = client.chat.completions.create(
    model="$MODEL",
    messages=[{"role": "user", "content": "Say hello"}]
)

print(response.choices[0].message.content)
PYTHON

# Run it
export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"
python test_gateway.py
\`\`\`

---

## Method 2: OpenAI Codex CLI

### Setup

\`\`\`bash
# Install Codex CLI (if not already installed)
npm install -g @openai/codex
# Or: brew install --cask codex

# Set API key
export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"

# Add to shell profile for persistence
echo 'export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"' >> ~/.zshrc  # macOS
echo 'export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"' >> ~/.bashrc # Linux
\`\`\`

### Usage

\`\`\`bash
# Launch Codex CLI (interactive mode)
codex -c 'model_provider="litellm-gateway"' -c 'model="$MODEL"'

# Or create an alias for convenience
echo 'alias codex-gateway=\"codex -c model_provider=\\\"litellm-gateway\\\" -c model=\\\"$MODEL\\\"\"' >> ~/.zshrc
source ~/.zshrc

# Now just run
codex-gateway
\`\`\`

### One-Shot Commands

\`\`\`bash
# Execute a single command
codex exec -c 'model_provider="litellm-gateway"' -c 'model="$MODEL"' "Write a Python function to calculate fibonacci"

# With alias
codex-gateway exec "Explain the purpose of this file" @README.md
\`\`\`

### Verification

When you launch Codex, check the status bar shows:
\`\`\`
OpenAI Codex v0.130.0
--------
model: $MODEL
provider: litellm-gateway
--------
\`\`\`

If it shows \`provider: openai\`, you forgot the \`-c\` flag!

---

## Verification: Both Methods Use Gateway

### Check Gateway Logs

\`\`\`bash
# Watch gateway logs in real-time
aws logs tail /ecs/litellm --follow --region us-west-2 --filter-pattern "POST"

# In another terminal, test Method 1
curl -X POST "$GATEWAY_URL/chat/completions" \\
  -H "Authorization: Bearer \$OPENAI_API_KEY" \\
  -d '{"model":"$MODEL","messages":[{"role":"user","content":"test"}]}'

# Then test Method 2
codex-gateway exec "Say hi"

# You should see both requests in the logs! ✅
\`\`\`

### Check LiteLLM UI

\`\`\`bash
# Open LiteLLM dashboard
open ${GATEWAY_URL%/v1}/ui

# Login with master key
# Navigate to "Analytics" or "Logs"
# You'll see requests from both curl and Codex CLI
\`\`\`

---

## Troubleshooting

### Issue: Codex connects to api.openai.com instead of gateway

**Symptom:** Error mentions \`api.openai.com\` or shows \`provider: openai\`

**Fix:** You must use the \`-c\` flag to override the provider:
\`\`\`bash
codex -c 'model_provider="litellm-gateway"' -c 'model="$MODEL"'
\`\`\`

Or use the alias:
\`\`\`bash
codex-gateway
\`\`\`

### Issue: 401 Unauthorized

**Symptom:** \`Incorrect API key provided\`

**Fix:** Check your API key is set correctly:
\`\`\`bash
echo \$OPENAI_API_KEY  # Should show: sk-litellm-...

# If empty, set it
export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"
\`\`\`

### Issue: Connection refused

**Symptom:** \`curl: (7) Failed to connect\`

**Fix:** Check gateway is accessible:
\`\`\`bash
# Test gateway health
curl ${GATEWAY_URL%/v1}/health

# If this fails, check:
# 1. Your IP is in the allowed CIDR range
# 2. Gateway is deployed and running
# 3. No firewall blocking access
\`\`\`

---

## What's Happening Behind the Scenes

Both methods follow the same flow:

\`\`\`
Client (curl/Codex CLI)
    ↓
    HTTP POST $GATEWAY_URL/chat/completions
    Authorization: Bearer sk-litellm-xxxxx
    ↓
LiteLLM Gateway
    - Validates API key
    - Checks user quota
    - Logs request
    ↓
Amazon Bedrock Mantle API
    ↓
OpenAI GPT model (openai.gpt-oss-safeguard-120b)
    ↓
Response streamed back through gateway
    ↓
Client receives response
\`\`\`

**Both methods:**
- ✅ Use the same API key
- ✅ Go through the same gateway
- ✅ Subject to the same quotas
- ✅ Logged in the same analytics

The only difference is the **client tool** (curl vs Codex CLI).

---

## Notes

- Do not commit API keys
- The gateway returns 429 on budget exhaustion — request a limit increase via your ops channel
- Codex CLI provides a better experience (file context, multi-turn conversations, code editing)
- curl/API is simpler for testing and CI/CD integration
- Run \`./uninstall.sh\` to remove the managed config block from \`~/.codex/config.toml\`
- Rotation: request a new key; the old one is revoked.
- If key expires, run: ./refresh-key.sh
SETUP

# Copy refresh script if it exists
REFRESH_SCRIPT="$(dirname "$0")/../../source/refresh-codex-key.sh"
if [[ -f "$REFRESH_SCRIPT" ]]; then
  cp "$REFRESH_SCRIPT" "$OUTDIR/refresh-key.sh"
  chmod +x "$OUTDIR/refresh-key.sh"

  # Update GATEWAY_URL in the script
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|GATEWAY_URL=\${GATEWAY_URL:-.*}|GATEWAY_URL=\${GATEWAY_URL:-${GATEWAY_URL%/v1}}|g" "$OUTDIR/refresh-key.sh"
  else
    sed -i "s|GATEWAY_URL=\${GATEWAY_URL:-.*}|GATEWAY_URL=\${GATEWAY_URL:-${GATEWAY_URL%/v1}}|g" "$OUTDIR/refresh-key.sh"
  fi
fi

echo "Wrote $OUTDIR/"
ls -1 "$OUTDIR"
