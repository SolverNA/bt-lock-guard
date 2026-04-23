#!/bin/bash
# bt-lock-guard installer
# Usage: curl -fsSL https://raw.githubusercontent.com/SolVerNA/bt-lock-guard/master/install.sh | sudo bash

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run with sudo: sudo bash install.sh"
command -v python3   > /dev/null || error "python3 not found"
command -v systemctl > /dev/null || error "systemd not found"

# ── MAC address ───────────────────────────────────────────────────────────────
echo ""
read -r -p "  Enter Bluetooth MAC address (AA:BB:CC:DD:EE:FF): " MAC
MAC="${MAC^^}"
[[ "$MAC" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || error "Invalid MAC: $MAC"
echo ""

# ── Dependencies ──────────────────────────────────────────────────────────────
info "Installing dependencies..."
apt-get update -qq 2>/dev/null || warn "apt-get update had errors"
apt-get install -y bluez python3-pyqt5 python3-dbus 2>/dev/null || \
    error "apt-get failed. Check internet connection."

# ── Files ────────────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
REPO="https://raw.githubusercontent.com/SolVerNA/bt-lock-guard/master"

info "Downloading..."
curl -fsSL "$REPO/src/bt-lock-daemon"          -o "$TMP/bt-lock-daemon"
curl -fsSL "$REPO/src/bt-lock-tray"            -o "$TMP/bt-lock-tray"
curl -fsSL "$REPO/src/bt-lock-daemon@.service" -o "$TMP/bt-lock-daemon@.service"
curl -fsSL "$REPO/src/bt-lock-tray.service"    -o "$TMP/bt-lock-tray.service"

info "Installing files..."
install -Dm755 "$TMP/bt-lock-daemon"          /usr/local/bin/bt-lock-daemon
install -Dm755 "$TMP/bt-lock-tray"            /usr/local/bin/bt-lock-tray
install -Dm644 "$TMP/bt-lock-daemon@.service" /usr/lib/systemd/user/bt-lock-daemon@.service
install -Dm644 "$TMP/bt-lock-tray.service"    /usr/lib/systemd/user/bt-lock-tray.service

# ── Config ────────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$USER}"
info "Configuring for user $REAL_USER..."

su -l "$REAL_USER" -s /bin/bash -c "
    mkdir -p ~/.config/bt-lock-guard ~/.local/share/bt-lock-guard
    cat > ~/.config/bt-lock-guard/config.json << 'CFGEOF'
{
  \"mac\": \"$MAC\",
  \"threshold\": -80,
  \"misses\": 3,
  \"interval\": 1,
  \"grace\": 30,
  \"enabled\": true
}
CFGEOF
    systemctl --user daemon-reload
    systemctl --user enable --now bt-lock-daemon@$MAC
    systemctl --user enable --now bt-lock-tray
" || warn "Could not start services — run: make setup MAC=$MAC"

rm -rf "$TMP"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  bt-lock-guard installed!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Tray icon appears near Wi-Fi/clock in KDE panel."
echo "  Walk away with your phone — screen will lock."
echo ""
echo "  Logs:       journalctl --user -u bt-lock-daemon@$MAC -f"
echo "  Uninstall:  sudo make uninstall"
echo ""
