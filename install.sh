#!/bin/bash
# bt-lock-guard installer
# Usage: curl -fsSL https://raw.githubusercontent.com/SolVerNA/bt-lock-guard/master/install.sh | sudo bash

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }
step()  { echo -e "${CYAN}[>]${NC} $*"; }

[[ $EUID -ne 0 ]] && error "Run with sudo: curl ... | sudo bash"
command -v python3   >/dev/null || error "python3 not found"
command -v systemctl >/dev/null || error "systemd not found"
command -v curl      >/dev/null || error "curl not found"

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
        warn "Unknown package manager — install manually: bluez, bluez-utils, python-pyqt5, python-dbus"
        ;;
esac

# ── Files ─────────────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch_raw() {
    local path="$1" out="$2" ok=1
    for ref in master main; do
        if curl -fsSL "https://raw.githubusercontent.com/SolverNA/bt-lock-guard/${ref}/${path}" \
                -o "$out" 2>/dev/null; then
            ok=0; break
        fi
    done
    return "$ok"
}

info "Downloading files..."
fetch_raw "src/bt-lock-daemon"          "$TMP/bt-lock-daemon"          || error "Failed: bt-lock-daemon"
fetch_raw "src/bt-lock-tray"            "$TMP/bt-lock-tray"            || error "Failed: bt-lock-tray"
fetch_raw "src/bt-lock-daemon@.service" "$TMP/bt-lock-daemon@.service" || error "Failed: bt-lock-daemon@.service"
fetch_raw "src/bt-lock-tray.service"    "$TMP/bt-lock-tray.service"    || error "Failed: bt-lock-tray.service"

info "Installing files..."
install -Dm755 "$TMP/bt-lock-daemon"          /usr/local/bin/bt-lock-daemon
install -Dm755 "$TMP/bt-lock-tray"            /usr/local/bin/bt-lock-tray
install -Dm644 "$TMP/bt-lock-daemon@.service" /usr/lib/systemd/user/bt-lock-daemon@.service
install -Dm644 "$TMP/bt-lock-tray.service"    /usr/lib/systemd/user/bt-lock-tray.service

# ── Bluetooth device scanner ──────────────────────────────────────────────────
# MAC result is written to a temp file to avoid any subshell/stdin scoping issues
# (su -l inherits the curl pipe as stdin and can consume bytes from it)
MAC_FILE="$(mktemp)"
trap 'rm -rf "$TMP" "$MAC_FILE"' EXIT

pick_device() {
    local result_file="$1"

    step "Powering on Bluetooth..."
    bluetoothctl power on >/dev/null 2>&1 || true

    step "Scanning for Bluetooth devices (10 seconds)..."
    bluetoothctl scan on >/dev/null 2>&1 &
    local SCAN_PID=$!

    local i
    for i in $(seq 1 10); do
        local filled empty bar
        filled="$(printf '#%.0s' $(seq 1 "$i"))"
        empty="$(printf '.%.0s' $(seq "$((i+1))" 10) 2>/dev/null || true)"
        bar="${filled}${empty}"
        printf "\r  [%-10s] %2d/10s " "$bar" "$i" >/dev/tty
        sleep 1
    done
    printf "\r%-40s\r" " " >/dev/tty

    kill "$SCAN_PID" 2>/dev/null || true
    wait "$SCAN_PID" 2>/dev/null || true

    local dev_raw
    dev_raw="$(bluetoothctl devices 2>/dev/null | grep '^Device ' || true)"

    if [[ -z "$dev_raw" ]]; then
        warn "No Bluetooth devices found."
        warn "Make sure your device is nearby, Bluetooth is ON and discoverable."
        printf "\n  Enter MAC address manually (AA:BB:CC:DD:EE:FF): " >/dev/tty
        local m; read -r m </dev/tty
        printf '%s' "${m^^}" > "$result_file"
        return
    fi

    local -a macs=() names=()
    local n=0
    while IFS= read -r line; do
        [[ "$line" =~ ^Device[[:space:]]([0-9A-Fa-f:]{17})[[:space:]](.*)$ ]] || continue
        macs+=("${BASH_REMATCH[1]^^}")
        names+=("${BASH_REMATCH[2]}")
        n=$((n+1))
    done <<< "$dev_raw"

    if [[ $n -eq 0 ]]; then
        warn "Could not parse device list."
        printf "\n  Enter MAC address manually (AA:BB:CC:DD:EE:FF): " >/dev/tty
        local m; read -r m </dev/tty
        printf '%s' "${m^^}" > "$result_file"
        return
    fi

    {
        echo ""
        printf "  %-5s  %-19s  %s\n" "No." "MAC" "Device name"
        printf "  %-5s  %-19s  %s\n" "─────" "───────────────────" "────────────────────────────"
        local i
        for i in "${!macs[@]}"; do
            printf "  %-5s  %-19s  %s\n" "$((i+1))" "${macs[$i]}" "${names[$i]}"
        done
        echo ""
    } >/dev/tty

    local choice
    while true; do
        printf "  Select device [1-%d]: " "$n" >/dev/tty
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
            printf '%s' "${macs[$((choice-1))]}" > "$result_file"
            info "Selected: ${names[$((choice-1))]}  (${macs[$((choice-1))]})"
            break
        fi
        warn "Enter a number between 1 and $n."
    done
}

pick_device "$MAC_FILE"
MAC="$(cat "$MAC_FILE")"
[[ "$MAC" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || error "Invalid MAC: '$MAC'"

# ── Config ────────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID="$(id -u "$REAL_USER")"

info "Writing config for user $REAL_USER..."
CFG_DIR="/home/$REAL_USER/.config/bt-lock-guard"
STATE_DIR="/home/$REAL_USER/.local/share/bt-lock-guard"
mkdir -p "$CFG_DIR" "$STATE_DIR"
printf '{"mac":"%s","threshold":-80,"misses":3,"interval":1,"grace":30,"enabled":true}' "$MAC" \
    > "$CFG_DIR/config.json"
chown -R "$REAL_USER:$REAL_USER" "$CFG_DIR" "$STATE_DIR"

# ── Start services ────────────────────────────────────────────────────────────
# XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS are required for systemctl --user
# to reach the running user D-Bus session when invoked from a root context.
# runuser (util-linux) is more reliable than su -l for this purpose on Arch.
info "Starting services..."
XDG_RT="/run/user/$REAL_UID"
DBUS_SOCK="unix:path=/run/user/$REAL_UID/bus"

start_user_svc() {
    runuser -u "$REAL_USER" -- env \
        XDG_RUNTIME_DIR="$XDG_RT" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_SOCK" \
        systemctl --user "$@"
}

start_user_svc daemon-reload
start_user_svc enable --now "bt-lock-daemon@$MAC" \
    || warn "Could not enable daemon — run: systemctl --user enable --now bt-lock-daemon@$MAC"
start_user_svc enable --now bt-lock-tray \
    || warn "Could not enable tray — run: systemctl --user enable --now bt-lock-tray"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  bt-lock-guard installed!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Device : $MAC"
echo "  Tray icon appears near Wi-Fi/clock in KDE panel."
echo "  Walk away with your phone — screen will lock."
echo ""
echo "  If the tray icon is missing, run:"
echo "    systemctl --user enable --now bt-lock-tray"
echo ""
echo "  Logs:       journalctl --user -u bt-lock-daemon@$MAC -f"
echo "  Uninstall:  sudo make uninstall"
echo ""
