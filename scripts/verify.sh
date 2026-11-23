#!/usr/bin/env bash
set -u
echo "=== Host ==="
uname -m; . /etc/os-release; echo "$PRETTY_NAME"
echo "=== RDP ==="
ps -eo args | grep '[w]eston.*backend=rdp' | head -2
echo "=== Waydroid ==="
waydroid status
sudo waydroid shell wm size
sudo waydroid shell wm density
echo "=== Android ==="
sudo waydroid shell getprop sys.boot_completed
sudo waydroid shell settings get secure default_input_method
echo "=== Services ==="
systemctl --user is-enabled pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service
systemctl --user is-active pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service
echo "=== Relay ==="
journalctl --user -u pickle-rdp-android-input.service --no-pager -n 12 | grep -E 'RDP_ANDROID_IME_READY|INPUT_ERROR|INPUT_OK|Failed|Started' || true
