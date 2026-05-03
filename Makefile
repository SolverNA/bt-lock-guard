NAME    = bt-lock-guard
VERSION = 1.0.0
PREFIX  ?= /usr/local
MAC_RE  = ^([0-9A-F]{2}:){5}[0-9A-F]{2}$$

.PHONY: all install uninstall setup help

all: help

help:
	@echo "Targets:"
	@echo "  sudo make install                          install files + tray (pick device from GUI)"
	@echo "  sudo make install MAC=AA:BB:CC:DD:EE:FF   install + configure device immediately"
	@echo "  sudo make uninstall                        remove everything"
	@echo "       make setup  MAC=AA:BB:CC:DD:EE:FF     re-run user setup"

install:
	@echo "==> Installing $(NAME)..."
	@echo "==> Installing dependencies..."; \
	if command -v pacman >/dev/null 2>&1; then \
		pacman -Sy --noconfirm bluez bluez-utils python-pyqt5 python-dbus; \
		systemctl enable --now bluetooth.service || echo "[!] Run: sudo systemctl enable --now bluetooth.service"; \
	elif command -v apt-get >/dev/null 2>&1; then \
		apt-get update -qq || true; \
		apt-get install -y bluez python3-pyqt5 python3-dbus; \
	elif command -v dnf >/dev/null 2>&1; then \
		dnf install -y bluez python3-pyqt5 python3-dbus; \
	else \
		echo "[!] Unknown package manager — install bluez, bluez-utils, python-pyqt5, python-dbus manually."; \
	fi

	install -Dm755 src/bt-lock-daemon           $(DESTDIR)$(PREFIX)/bin/bt-lock-daemon
	install -Dm755 src/bt-lock-tray             $(DESTDIR)$(PREFIX)/bin/bt-lock-tray
	install -Dm644 src/bt-lock-daemon@.service  $(DESTDIR)/usr/lib/systemd/user/bt-lock-daemon@.service
	install -Dm644 src/bt-lock-tray.service     $(DESTDIR)/usr/lib/systemd/user/bt-lock-tray.service
	@if command -v gcc >/dev/null 2>&1; then \
	    echo "==> Building bt-rssi helper (RSSI for BR/EDR)..."; \
	    gcc -O2 -o $(DESTDIR)$(PREFIX)/bin/bt-rssi src/bt-rssi.c -lbluetooth \
	        && setcap cap_net_raw+ep $(DESTDIR)$(PREFIX)/bin/bt-rssi \
	        && echo "==> bt-rssi built — RSSI enabled" \
	        || echo "[!] bt-rssi build failed — RSSI unavailable"; \
	else \
	    echo "[!] gcc not found — skipping bt-rssi, RSSI unavailable"; \
	fi

	systemctl daemon-reload 2>/dev/null || true

	@if [ -n "$(MAC)" ]; then \
		echo "$(MAC)" | tr '[:lower:]' '[:upper:]' | grep -Eq '$(MAC_RE)' \
		    || (echo "Invalid MAC: $(MAC)"; exit 1); \
		REAL_USER="$${SUDO_USER:-$$USER}"; \
		MAC_UPPER="$$(echo "$(MAC)" | tr '[:lower:]' '[:upper:]')"; \
		su -l "$$REAL_USER" -s /bin/bash -c " \
		    mkdir -p ~/.config/bt-lock-guard ~/.local/share/bt-lock-guard; \
		    printf '%s' '{\"mac\":\"$$MAC_UPPER\",\"threshold\":-80,\"misses\":3,\"interval\":1,\"grace\":30,\"enabled\":true}' \
		        > ~/.config/bt-lock-guard/config.json; \
		    systemctl --user daemon-reload; \
		    systemctl --user enable --now bt-lock-daemon@$$MAC_UPPER; \
		    systemctl --user enable --now bt-lock-tray; \
		" || echo "[!] Run 'make setup MAC=$$MAC_UPPER' as your normal user"; \
		echo ""; \
		echo "==> Device: $$(echo "$(MAC)" | tr '[:lower:]' '[:upper:]')"; \
	else \
		REAL_USER="$${SUDO_USER:-$$USER}"; \
		su -l "$$REAL_USER" -s /bin/bash -c " \
		    mkdir -p ~/.config/bt-lock-guard ~/.local/share/bt-lock-guard; \
		    systemctl --user daemon-reload; \
		    systemctl --user enable --now bt-lock-tray; \
		" || true; \
		echo ""; \
		echo "==> No device configured yet."; \
		echo "    Open the tray icon → 'Scan & pick device' to bind your phone/watch."; \
		echo "    Or re-run: sudo make install MAC=AA:BB:CC:DD:EE:FF"; \
	fi

	@echo "==> $(NAME) installed! Tray icon will appear near Wi-Fi/clock."

setup:
	@[ -n "$(MAC)" ] || (echo "Usage: make setup MAC=AA:BB:CC:DD:EE:FF"; exit 1)
	@echo "$(MAC)" | tr '[:lower:]' '[:upper:]' | grep -Eq '$(MAC_RE)' || (echo "Invalid MAC: $(MAC)"; exit 1)
	@MAC_UPPER="$$(echo "$(MAC)" | tr '[:lower:]' '[:upper:]')"; \
	mkdir -p ~/.config/bt-lock-guard ~/.local/share/bt-lock-guard; \
	printf '%s' '{"mac":"'"$$MAC_UPPER"'","threshold":-80,"misses":3,"interval":1,"grace":30,"enabled":true}' \
	    > ~/.config/bt-lock-guard/config.json; \
	systemctl --user daemon-reload; \
	systemctl --user enable --now bt-lock-daemon@$$MAC_UPPER; \
	systemctl --user enable --now bt-lock-tray
	@echo "==> Services started."

uninstall:
	@echo "==> Uninstalling $(NAME)..."
	REAL_USER="$${SUDO_USER:-$$USER}"; \
	su -l "$$REAL_USER" -s /bin/bash -c " \
	    systemctl --user stop bt-lock-tray 2>/dev/null || true; \
	    systemctl --user disable bt-lock-tray 2>/dev/null || true; \
	    systemctl --user stop 'bt-lock-daemon@*' 2>/dev/null || true; \
	    systemctl --user disable 'bt-lock-daemon@*' 2>/dev/null || true; \
	    systemctl --user daemon-reload; \
	" || true
	rm -f  $(PREFIX)/bin/bt-lock-daemon
	rm -f  $(PREFIX)/bin/bt-lock-tray
	rm -f  $(PREFIX)/bin/bt-rssi
	rm -f  /usr/lib/systemd/user/bt-lock-daemon@.service
	rm -f  /usr/lib/systemd/user/bt-lock-tray.service
	systemctl daemon-reload 2>/dev/null || true
	@echo "==> Uninstalled. Config kept in ~/.config/bt-lock-guard/"
