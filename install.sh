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
command -v curl      > /dev/null || error "curl not found"

# ── MAC address ───────────────────────────────────────────────────────────────
echo ""
read -r -p "  Enter Bluetooth MAC address (AA:BB:CC:DD:EE:FF): " MAC
MAC="${MAC^^}"
[[ "$MAC" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || error "Invalid MAC: $MAC"
echo ""

# ── Package manager detection ─────────────────────────────────────────────────
detect_pm() {
    if   command -v pacman  &>/dev/null; then echo "pacman"
    elif command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf     &>/dev/null; then echo "dnf"
    else echo "unknown"
    fi
}

# ── Dependencies ──────────────────────────────────────────────────────────────
info "Installing dependencies..."
PM="$(detect_pm)"
case "$PM" in
    pacman)
        pacman -Sy --noconfirm bluez bluez-utils python-pyqt5 python-dbus \
            || error "pacman failed. Check internet connection."
        systemctl enable --now bluetooth.service \
            || warn "Could not enable bluetooth.service — run: sudo systemctl enable --now bluetooth.service"
        ;;
    apt)
        apt-get update -qq 2>/dev/null || warn "apt-get update had errors"
        apt-get install -y bluez python3-pyqt5 python3-dbus \
            || error "apt-get failed. Check internet connection."
        ;;
    dnf)
        dnf install -y bluez python3-pyqt5 python3-dbus \
            || error "dnf failed. Check internet connection."
        ;;
    *)
        warn "Unknown package manager — skipping auto-install."
        warn "Make sure these are installed: bluez, bluez-utils, python-pyqt5, python-dbus"
        ;;
esac

# ── Files ────────────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"

fetch_raw() {
    local path="$1"
    local out="$2"
    local ok=1
    for ref in master main; do
        if curl -fsSL "https://raw.githubusercontent.com/SolverNA/bt-lock-guard/${ref}/${path}" -o "$out"; then
            ok=0
            break
        fi
    done
    return "$ok"
}

info "Downloading..."
fetch_raw "src/bt-lock-daemon"          "$TMP/bt-lock-daemon"          || error "Failed to download bt-lock-daemon"
fetch_raw "src/bt-lock-tray"            "$TMP/bt-lock-tray"            || error "Failed to download bt-lock-tray"
fetch_raw "src/bt-lock-daemon@.service" "$TMP/bt-lock-daemon@.service" || error "Failed to download bt-lock-daemon@.service"
fetch_raw "src/bt-lock-tray.service"    "$TMP/bt-lock-tray.service"    || error "Failed to download bt-lock-tray.service"

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
