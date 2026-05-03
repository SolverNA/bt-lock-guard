# bt-lock-guard

Locks your KDE screen when your Bluetooth device (phone/watch) leaves range.
Shows a **system tray icon** with real-time signal graph, toggle switch, and threshold slider.

```
Phone moves away → RSSI drops below threshold
        ↓
bt-lock-daemon detects N consecutive misses
        ↓
Screen locks (qdbus / loginctl)
        ↓
Phone returns → unlock → grace period → monitoring resumes
```

## Features

- System tray icon (near Wi-Fi/clock in KDE panel)
- Click → popup with:
  - **Toggle switch** — enable / disable guard instantly
  - **Threshold slider** — set lock distance (-100 to -30 dBm)
  - **Real-time RSSI graph** — 60-second history with dBm values
- Per-session config — changes take effect immediately
- Grace period after unlock (lets Bluetooth reconnect before re-arming)
- Works with any Bluetooth device: phone, watch, tag

## Install

### One-liner (auto-detects Arch/Manjaro, Debian/Ubuntu/Kali, Fedora)

```bash
curl -fsSL https://raw.githubusercontent.com/SolVerNA/bt-lock-guard/master/install.sh | sudo bash
```

Installer detects your package manager, installs the right dependencies, and asks for the target Bluetooth MAC during setup.

### From source

```bash
git clone https://github.com/SolVerNA/bt-lock-guard
cd bt-lock-guard
sudo make install MAC=AA:BB:CC:DD:EE:FF
```

`make install` detects and installs required packages automatically.

### Arch Linux / Manjaro (manual)

```bash
sudo pacman -S bluez bluez-utils python-pyqt5 python-dbus
sudo systemctl enable --now bluetooth.service
git clone https://github.com/SolVerNA/bt-lock-guard
cd bt-lock-guard
sudo make install MAC=AA:BB:CC:DD:EE:FF
```

### Debian / Ubuntu / Kali (manual)

```bash
sudo apt-get install bluez python3-pyqt5 python3-dbus
git clone https://github.com/SolVerNA/bt-lock-guard
cd bt-lock-guard
sudo make install MAC=AA:BB:CC:DD:EE:FF
```

### Device selection in tray window

There is currently **no device picker** in the tray popup.  
The popup shows status and controls (enable/disable + threshold), while device binding is configured by MAC during install/setup.

## Requirements

| Package | Arch / Manjaro | Debian / Ubuntu |
|---------|---------------|-----------------|
| Bluetooth daemon + tools | `bluez` | `bluez` |
| l2ping, hcitool | `bluez-utils` | included in `bluez` |
| Qt5 tray UI | `python-pyqt5` | `python3-pyqt5` |
| D-Bus bindings | `python-dbus` | `python3-dbus` |

- systemd + KDE Plasma (X11 or Wayland)

## Threshold guide

| dBm | Distance (approx) | Use case |
|-----|-------------------|----------|
| -40 | ~1m (same room) | Very tight — desk only |
| -60 | ~3–5m | Same room |
| -70 | ~5–10m | Leave room |
| -80 | ~10–15m | Leave apartment |
| -90 | ~20m+ | Leave building |

> Start at -80 dBm and adjust using the live graph in the tray popup.

## Logs

```bash
# Daemon
journalctl --user -u bt-lock-daemon@AA:BB:CC:DD:EE:FF -f

# Tray
journalctl --user -u bt-lock-tray -f
```

## Uninstall

```bash
git clone https://github.com/SolVerNA/bt-lock-guard
cd bt-lock-guard
sudo make uninstall
```

Or if you already have the repo cloned:

```bash
sudo make uninstall
```

Config is kept at `~/.config/bt-lock-guard/config.json`.

## License

MIT — SolVerNA
