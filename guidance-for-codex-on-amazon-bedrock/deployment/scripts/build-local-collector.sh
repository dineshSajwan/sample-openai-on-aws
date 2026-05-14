#!/usr/bin/env bash
# Build/download ADOT collector binaries for local deployment
# Downloads official ADOT collector releases for multiple platforms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/../binaries"
ADOT_VERSION="${ADOT_VERSION:-v0.40.0}"

usage() {
  cat <<EOF
Usage: build-local-collector.sh [options]

Downloads AWS Distro for OpenTelemetry collector binaries for local deployment.

Options:
  --version VERSION    ADOT collector version (default: $ADOT_VERSION)
  --platform PLATFORM  Build single platform: darwin-arm64, darwin-amd64, linux-amd64, windows-amd64
  --all               Build all platforms (default)
  -h, --help          Show this help

Examples:
  # Download all platforms
  ./build-local-collector.sh --all

  # Download specific platform
  ./build-local-collector.sh --platform darwin-arm64
EOF
}

PLATFORMS=()
BUILD_ALL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) ADOT_VERSION="$2"; shift 2;;
    --platform) PLATFORMS+=("$2"); BUILD_ALL=false; shift 2;;
    --all) BUILD_ALL=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [[ "$BUILD_ALL" == "true" ]]; then
  PLATFORMS=("darwin-arm64" "darwin-amd64" "linux-amd64" "windows-amd64")
fi

mkdir -p "$BINARIES_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }
ok() { echo "[$(date +%H:%M:%S)] ✓ $*"; }

# ADOT collector GitHub release URLs
BASE_URL="https://github.com/aws-observability/aws-otel-collector/releases/download"

download_binary() {
  local platform=$1
  local output_name="otelcol-local-${platform}"

  case "$platform" in
    darwin-arm64)
      url="$BASE_URL/$ADOT_VERSION/aws-otel-collector_darwin_arm64"
      ;;
    darwin-amd64)
      url="$BASE_URL/$ADOT_VERSION/aws-otel-collector_darwin_amd64"
      ;;
    linux-amd64)
      url="$BASE_URL/$ADOT_VERSION/aws-otel-collector_linux_amd64"
      ;;
    windows-amd64)
      url="$BASE_URL/$ADOT_VERSION/aws-otel-collector_windows_amd64.exe"
      output_name="${output_name}.exe"
      ;;
    *)
      echo "Unsupported platform: $platform" >&2
      return 1
      ;;
  esac

  log "Downloading $platform from $url"

  if curl -fSL "$url" -o "$BINARIES_DIR/$output_name"; then
    chmod +x "$BINARIES_DIR/$output_name"
    size=$(du -h "$BINARIES_DIR/$output_name" | cut -f1)
    ok "Downloaded $output_name ($size)"
  else
    echo "Failed to download $platform" >&2
    return 1
  fi
}

log "Downloading ADOT collector $ADOT_VERSION"
log "Output directory: $BINARIES_DIR"

for platform in "${PLATFORMS[@]}"; do
  download_binary "$platform"
done

ok "All binaries downloaded successfully"
ok "Binaries available in: $BINARIES_DIR"

cat <<EOF

Next steps:
  1. Binaries are ready for distribution
  2. Run 'cxwb distribute' to create developer bundles
  3. Bundles will include appropriate binary for each platform

Available binaries:
EOF

ls -lh "$BINARIES_DIR"/otelcol-local-* 2>/dev/null || echo "  (none yet)"
