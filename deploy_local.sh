#!/usr/bin/env bash
#
# deploy_local.sh — Build and deploy LiquidEditor to a connected iOS device
#
# Usage:
#   ./deploy_local.sh              # Auto-detect device, build & install
#   ./deploy_local.sh --run        # Build, install, and launch the app
#   ./deploy_local.sh --release    # Build Release config instead of Debug
#   ./deploy_local.sh --list       # List connected devices and exit
#   ./deploy_local.sh --clean      # Clean build before deploying
#
# Requirements:
#   - Xcode with a valid Apple Developer signing identity
#   - A connected iOS device (USB or network)
#   - xcodegen (brew install xcodegen)
#

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="LiquidEditor"
SCHEME="LiquidEditor"
BUNDLE_ID="com.liquideditor.app"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
APP_PATH=""

CONFIG="Debug"
SHOULD_RUN=false
SHOULD_CLEAN=false
SHOULD_LIST=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─── Helpers ────────────────────────────────────────────────────────────────────

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}\n"; }

elapsed() {
    local start=$1
    local end
    end=$(date +%s)
    echo "$(( end - start ))s"
}

# ─── Parse Arguments ────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run)     SHOULD_RUN=true ;;
        --release) CONFIG="Release" ;;
        --clean)   SHOULD_CLEAN=true ;;
        --list)    SHOULD_LIST=true ;;
        --help|-h)
            echo "Usage: $0 [--run] [--release] [--clean] [--list] [--help]"
            echo ""
            echo "Options:"
            echo "  --run       Launch the app after installing"
            echo "  --release   Build with Release configuration (default: Debug)"
            echo "  --clean     Clean build folder before building"
            echo "  --list      List connected devices and exit"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# ─── Preflight Checks ──────────────────────────────────────────────────────────

step "Preflight Checks"

# Check xcodegen
if ! command -v xcodegen &>/dev/null; then
    error "xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi
success "xcodegen found"

# Check xcodebuild
if ! command -v xcodebuild &>/dev/null; then
    error "xcodebuild not found. Install Xcode from the App Store."
    exit 1
fi
success "xcodebuild found ($(xcodebuild -version | head -1))"

# ─── Device Discovery ──────────────────────────────────────────────────────────

step "Device Discovery"

# Use xcrun devicectl to find connected devices (Xcode 15+)
DEVICE_JSON=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null || true)

if [[ -z "$DEVICE_JSON" ]]; then
    # Fallback: use xctrace to list devices
    warn "devicectl JSON output unavailable, using xctrace fallback"
    DEVICE_LIST=$(xcrun xctrace list devices 2>/dev/null | grep -E "^\S.+\(.+\)$" | grep -v "Simulator" || true)

    if [[ -z "$DEVICE_LIST" ]]; then
        error "No connected iOS devices found."
        echo ""
        echo "Troubleshooting:"
        echo "  1. Connect your device via USB"
        echo "  2. Unlock the device and trust this computer"
        echo "  3. Ensure Developer Mode is enabled (Settings > Privacy > Developer Mode)"
        exit 1
    fi

    if $SHOULD_LIST; then
        echo ""
        info "Connected devices:"
        echo "$DEVICE_LIST"
        exit 0
    fi

    # Pick the first device
    DEVICE_NAME=$(echo "$DEVICE_LIST" | head -1 | sed 's/ (.*//')
    DEVICE_ID=$(echo "$DEVICE_LIST" | head -1 | grep -oE '[A-Fa-f0-9-]{20,}')
    info "Found device: ${BOLD}${DEVICE_NAME}${NC} (${DEVICE_ID})"
else
    # Parse devicectl JSON for connected devices
    CONNECTED_DEVICES=$(echo "$DEVICE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
devices = data.get('result', {}).get('devices', [])
for d in devices:
    conn = d.get('connectionProperties', {})
    if conn.get('transportType') in ['wired', 'localNetwork', 'network']:
        name = d.get('deviceProperties', {}).get('name', 'Unknown')
        udid = d.get('hardwareProperties', {}).get('udid', d.get('identifier', ''))
        os_ver = d.get('deviceProperties', {}).get('osVersionNumber', '?')
        print(f'{udid}||{name}||{os_ver}')
" 2>/dev/null || true)

    if [[ -z "$CONNECTED_DEVICES" ]]; then
        error "No connected iOS devices found."
        echo ""
        echo "Troubleshooting:"
        echo "  1. Connect your device via USB"
        echo "  2. Unlock the device and trust this computer"
        echo "  3. Ensure Developer Mode is enabled (Settings > Privacy > Developer Mode)"
        echo ""
        echo "Run './deploy_local.sh --list' to see all known devices."
        exit 1
    fi

    if $SHOULD_LIST; then
        echo ""
        info "Connected devices:"
        echo "$CONNECTED_DEVICES" | while IFS='||' read -r udid name os_ver; do
            echo "  ${BOLD}${name}${NC} — iOS ${os_ver} (${udid})"
        done
        exit 0
    fi

    # Pick the first connected device
    FIRST_DEVICE=$(echo "$CONNECTED_DEVICES" | head -1)
    DEVICE_ID=$(echo "$FIRST_DEVICE" | cut -d'|' -f1)
    DEVICE_NAME=$(echo "$FIRST_DEVICE" | cut -d'|' -f3)  # after ||
    DEVICE_OS=$(echo "$FIRST_DEVICE" | cut -d'|' -f5)    # after second ||

    info "Found device: ${BOLD}${DEVICE_NAME}${NC} — iOS ${DEVICE_OS}"
    info "UDID: ${DEVICE_ID}"
fi

if [[ -z "${DEVICE_ID:-}" ]]; then
    error "Could not determine device UDID."
    exit 1
fi

# ─── Generate Xcode Project ────────────────────────────────────────────────────

step "Generating Xcode Project"

cd "$PROJECT_DIR"
xcodegen generate 2>&1 | while read -r line; do echo "  $line"; done
success "Project generated from project.yml"

# ─── Resolve Packages ──────────────────────────────────────────────────────────

step "Resolving Swift Packages"

xcodebuild -resolvePackageDependencies \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -quiet 2>&1 | while read -r line; do echo "  $line"; done
success "Packages resolved"

# ─── Clean (optional) ──────────────────────────────────────────────────────────

if $SHOULD_CLEAN; then
    step "Cleaning Build Folder"
    xcodebuild clean \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME" \
        -quiet 2>&1 | while read -r line; do echo "  $line"; done
    rm -rf "$BUILD_DIR"
    success "Build folder cleaned"
fi

# ─── Build ──────────────────────────────────────────────────────────────────────

step "Building ${SCHEME} (${CONFIG}) for device"

BUILD_START=$(date +%s)

mkdir -p "$BUILD_DIR"

# Build for the connected device with automatic signing
xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "id=${DEVICE_ID}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE="Automatic" \
    DEVELOPMENT_TEAM="8A3SPX9NY8" \
    2>&1 | tail -20

BUILD_ELAPSED=$(elapsed "$BUILD_START")

# Find the built .app
APP_PATH=$(find "${BUILD_DIR}/DerivedData" -name "${PROJECT_NAME}.app" -type d \
    -not -path "*/Intermediates/*" \
    -not -path "*-iphonesimulator/*" | head -1)

if [[ -z "$APP_PATH" ]]; then
    error "Build succeeded but could not find .app bundle"
    exit 1
fi

success "Build complete in ${BUILD_ELAPSED}"
info "App: ${APP_PATH}"

# ─── Install ────────────────────────────────────────────────────────────────────

step "Installing on ${DEVICE_NAME}"

INSTALL_START=$(date +%s)

# Try devicectl first (Xcode 15+), fall back to ios-deploy
if xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}" 2>&1; then
    INSTALL_ELAPSED=$(elapsed "$INSTALL_START")
    success "Installed in ${INSTALL_ELAPSED}"
elif command -v ios-deploy &>/dev/null; then
    warn "devicectl install failed, trying ios-deploy..."
    ios-deploy --id "${DEVICE_ID}" --bundle "${APP_PATH}" --no-wifi 2>&1
    INSTALL_ELAPSED=$(elapsed "$INSTALL_START")
    success "Installed via ios-deploy in ${INSTALL_ELAPSED}"
else
    error "Installation failed. Ensure the device is unlocked and trusted."
    exit 1
fi

# ─── Launch (optional) ─────────────────────────────────────────────────────────

if $SHOULD_RUN; then
    step "Launching ${PROJECT_NAME}"

    if xcrun devicectl device process launch --device "${DEVICE_ID}" "${BUNDLE_ID}" 2>&1; then
        success "App launched on ${DEVICE_NAME}"
    elif command -v ios-deploy &>/dev/null; then
        warn "devicectl launch failed, trying ios-deploy..."
        ios-deploy --id "${DEVICE_ID}" --bundle "${APP_PATH}" --justlaunch --no-wifi 2>&1
        success "App launched via ios-deploy"
    else
        warn "Could not auto-launch. Open the app manually on your device."
    fi
fi

# ─── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}━━━ Deploy Complete ━━━${NC}"
echo -e "  Device:  ${DEVICE_NAME}"
echo -e "  Config:  ${CONFIG}"
echo -e "  Bundle:  ${BUNDLE_ID}"
echo -e "  Build:   ${BUILD_ELAPSED}"
echo ""
