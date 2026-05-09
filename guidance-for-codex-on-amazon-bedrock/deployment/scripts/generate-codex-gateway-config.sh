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
model_provider = "openai"
model = "$MODEL"

[openai]
base_url = "$GATEWAY_URL"
# api_key read from \$OPENAI_API_KEY at runtime
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
# Codex Gateway — developer setup

Gateway: $GATEWAY_URL
Model:   $MODEL
Profile: $PROFILE_NAME

## 1. Get a per-user key

$KEY_SECTION

## 2. Install

\`\`\`bash
./install.sh
export OPENAI_API_KEY="sk-..."   # add to ~/.zshrc / ~/.bashrc
codex
\`\`\`

The install script writes a fenced managed block to \`~/.codex/config.toml\`.
Run \`./uninstall.sh\` to remove it.

## Notes

- Do not commit the key.
- The gateway will 429 on budget exhaustion — request a raise via your ops channel.
- Rotation: request a new key; the old one is revoked.
SETUP

echo "Wrote $OUTDIR/"
ls -1 "$OUTDIR"
