#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX=/opt/pickle-waydroid-rdp
CFG=/etc/pickle-waydroid-rdp
ADDRESS=""
PORT=3389
RDP_USER=pickle
ANDROID_IP=192.168.240.112
WIDTH=1280
HEIGHT=800
MODE=install

usage() {
  cat <<EOF
Usage: sudo bash scripts/install.sh --bind YOUR_PRIVATE_OR_TAILSCALE_IP [--user pickle] [--port 3389] [--android-ip 192.168.240.112]
       bash scripts/install.sh --check
Note: Install Waydroid and initialize its Android image separately before installing.
EOF
}
while (($#)); do
  case "$1" in
    --bind) ADDRESS="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --user) RDP_USER="$2"; shift 2;;
    --android-ip) ANDROID_IP="$2"; shift 2;;
    --check) MODE=check; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done
die() { echo "ERROR: $*" >&2; exit 1; }
test "$(uname -m)" = "aarch64" || die "Prebuilt binaries are ARM64 only."
if [ -f /etc/os-release ]; then
  . /etc/os-release
  [ "$ID" = "ubuntu" ] && [ "$VERSION_ID" = "26.04" ] || die "Verified target: Ubuntu 26.04 only."
fi
test -f "$ROOT/dist/weston-arm64.tar.xz" || die "Missing Weston binary archive."
test -f "$ROOT/dist/pickle-ime.apk" || die "Missing Android IME APK."
test -f "$ROOT/runtime/android_input.py" || die "Missing Android relay source."
(cd "$ROOT" && sha256sum -c CHECKSUMS.sha256) || die "Checksum mismatch."
if [ "$MODE" = "check" ]; then echo "CHECK_OK: architecture, OS, files, checksums"; exit 0; fi

[ "$(id -u)" -eq 0 ] || die "Run installer with sudo."
[ -n "$ADDRESS" ] || die "--bind is required (use private/Tailscale IP only)."
[[ "$ADDRESS" =~ ^[0-9a-fA-F.:]+$ ]] || die "--bind must be an IPv4/IPv6 address."
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && [ "$PORT" -gt 0 ] && [ "$PORT" -lt 65536 ] || die "Invalid port."
[[ "$ANDROID_IP" =~ ^[0-9.]+$ ]] || die "Invalid Android IP."
[[ "$RDP_USER" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] || die "Invalid username."
ip -o addr show | grep -Fq " $ADDRESS/" || die "Bind address is not assigned to a local interface."
OWNER="$(logname 2>/dev/null || true)"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then OWNER="$SUDO_USER"; fi
[ -n "$OWNER" ] && [ "$OWNER" != root ] || die "Run from the regular Waydroid user's shell using sudo."
id "$OWNER" >/dev/null || die "Owner user not found."
UID_NUM="$(id -u "$OWNER")"
for cmd in systemctl loginctl runuser openssl python3 adb tar waydroid; do
  command -v "$cmd" >/dev/null || die "Missing dependency $cmd"
done
[ -f /var/lib/waydroid/waydroid.cfg ] || die "Initialize Waydroid Android image first (sudo waydroid init)."
# A single Waydroid container cannot host different users' GUI sessions simultaneously.
CURRENT_SESSION="$(waydroid status 2>/dev/null || true)"
if grep -Fq "Session: RUNNING" <<<"$CURRENT_SESSION" &&
   ! grep -Fq "Session user: $OWNER(" <<<"$CURRENT_SESSION"; then
  die "Waydroid already has another user's session. Do not stop it; use a fresh VM or the existing owner."
fi
for p in libhangul.so.1 libfreerdp-server3.so.3; do
  ldconfig -p | grep -F "$p" >/dev/null || die "Missing library $p; see installation guide."
done

install -d -m 0755 "$PREFIX" "$PREFIX/weston"
install -d -m 0750 -o root -g "$(id -gn "$OWNER")" "$CFG"
tar --no-same-owner -xJf "$ROOT/dist/weston-arm64.tar.xz" -C "$PREFIX/weston"
install -m 0644 "$ROOT/dist/pickle-ime.apk" "$PREFIX/pickle-ime.apk"
install -m 0644 "$ROOT/runtime/android_input.py" "$PREFIX/android_input.py"
install -m 0755 "$ROOT/scripts/prepare-binder.sh" /usr/local/sbin/pickle-waydroid-prepare-binder

if [ ! -f "$CFG/users.sam" ]; then
  # A fresh account and certificate are generated for each server. Never ship these files.
  PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
  HASH="$(RDP_PASSWORD="$PASSWORD" python3 -c 'import os,sys;sys.stdout.buffer.write(os.environ["RDP_PASSWORD"].encode("utf-16le"))' | openssl dgst -md4 -provider legacy -binary | od -An -tx1 | tr -d ' \n')"
  printf '%s:PICKLE::%s:::\n' "$RDP_USER" "$HASH" > "$CFG/users.sam"
  printf 'RDP user: %s\nRDP password: %s\n' "$RDP_USER" "$PASSWORD" > "$CFG/first-login.txt"
  chmod 0600 "$CFG/first-login.txt"
  echo "New RDP login stored in $CFG/first-login.txt (root only)."
fi

if [ ! -f "$CFG/tls.key" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
    -subj /CN=pickle-waydroid-rdp -addext "subjectAltName=IP:$ADDRESS" \
    -keyout "$CFG/tls.key" -out "$CFG/tls.crt" >/dev/null 2>&1
fi
chown "root:$(id -gn "$OWNER")" "$CFG/users.sam" "$CFG/tls.key"
chmod 0640 "$CFG/users.sam" "$CFG/tls.key"
chmod 0644 "$CFG/tls.crt"

cat >"$CFG/weston.ini" <<EOF
[core]
backend=rdp
idle-time=0
[rdp]
refresh-rate=30
nla-ntlm-db=$CFG/users.sam
tls-key=$CFG/tls.key
tls-cert=$CFG/tls.crt
EOF
chmod 0644 "$CFG/weston.ini"

install -d -m 0755 /etc/systemd/system/waydroid-container.service.d
cat >/etc/systemd/system/waydroid-container.service.d/90-pickle-waydroid-binder.conf <<EOF
[Service]
ExecStartPre=/usr/local/sbin/pickle-waydroid-prepare-binder
EOF
systemctl daemon-reload
/usr/local/sbin/pickle-waydroid-prepare-binder
systemctl enable --now waydroid-container.service
loginctl enable-linger "$OWNER"

OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"
OWNER_GROUP="$(id -gn "$OWNER")"
SERVICE_DIR="$OWNER_HOME/.config/systemd/user"
for dir in "$OWNER_HOME/.config" "$OWNER_HOME/.config/systemd" "$SERVICE_DIR"; do
  install -d -m 0700 -o "$OWNER" -g "$OWNER_GROUP" "$dir"
done
cat >"$SERVICE_DIR/pickle-rdp-live.service" <<EOF
[Unit]
Description=Pickle Weston RDP NLA + Korean Unicode
After=pipewire.service
[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=%t
Environment=LD_LIBRARY_PATH=$PREFIX/weston/lib/aarch64-linux-gnu:$PREFIX/weston/lib/aarch64-linux-gnu/weston
Environment=PICKLE_RDP_ANDROID_SOCKET=%t/pickle-rdp-android.sock
Environment=PICKLE_RDP_LOCAL_CURSOR=1
Environment=PICKLE_RDP_COMPOSING_IME=1
ExecStartPre=/usr/bin/test -f $CFG/users.sam
ExecStart=$PREFIX/weston/bin/weston --backend=rdp --renderer=pixman --shell=kiosk-shell.so --socket=wayland-pickle-rdp-live --address=$ADDRESS --port=$PORT --width=$WIDTH --height=$HEIGHT --no-resizeable --idle-time=0 --config=$CFG/weston.ini
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target
EOF
cat >"$SERVICE_DIR/pickle-waydroid-live.service" <<EOF
[Unit]
Description=Pickle Android Waydroid UI
Requires=pickle-rdp-live.service
After=pickle-rdp-live.service pipewire-pulse.service
[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=%t
Environment=WAYLAND_DISPLAY=wayland-pickle-rdp-live
Environment=XDG_SESSION_TYPE=wayland
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
ExecStartPre=/usr/bin/test -S %t/wayland-pickle-rdp-live
ExecStart=/usr/bin/waydroid show-full-ui
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
EOF
cat >"$SERVICE_DIR/pickle-rdp-android-input.service" <<EOF
[Unit]
Description=Pickle Weston Unicode to Android IME
Requires=pickle-rdp-live.service
After=pickle-rdp-live.service pickle-waydroid-live.service
[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=%t
Environment=PYTHONUNBUFFERED=1
Environment=PICKLE_ANDROID_IME=com.badung.pickleime/.PickleIME
Environment=PICKLE_ANDROID_ADB_TARGET=$ANDROID_IP:5555
ExecStart=/usr/bin/python3 $PREFIX/android_input.py
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target
EOF
chown "$OWNER":"$OWNER" "$SERVICE_DIR"/pickle-*.service
chmod 0644 "$SERVICE_DIR"/pickle-*.service

# The user manager is kept alive by linger and can be started without a desktop login.
systemctl start "user@$UID_NUM.service"
userctl() {
  runuser -u "$OWNER" -- env XDG_RUNTIME_DIR="/run/user/$UID_NUM" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_NUM/bus" systemctl --user "$@"
}
userctl daemon-reload
userctl enable pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service
userctl start pickle-rdp-live.service
userctl start pickle-waydroid-live.service
READY=0
for i in $(seq 1 60); do
  adb connect "$ANDROID_IP:5555" >/dev/null 2>&1 || true
  if [ "$(adb -s "$ANDROID_IP:5555" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then READY=1; break; fi
  sleep 2
done
[ "$READY" = 1 ] || die "Android not ready yet. Check 'waydroid status' and rerun APK setup after boot."
# Some GAPPS images delay APK installation during package verification.
if ! timeout 90 adb -s "$ANDROID_IP:5555" install --no-incremental -r "$PREFIX/pickle-ime.apk"; then
  die "APK installation did not complete. Inspect Android package-verifier logs; do not disable verification permanently."
fi
adb -s "$ANDROID_IP:5555" shell ime enable com.badung.pickleime/.PickleIME
adb -s "$ANDROID_IP:5555" shell ime set com.badung.pickleime/.PickleIME
userctl start pickle-rdp-android-input.service
for svc in pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service; do
  [ "$(userctl is-active "$svc")" = active ] || die "$svc is not active."
done
waydroid status | grep -Fq "Session user: $OWNER(" || die "Android session is not owned by $OWNER."
waydroid status | grep -Fq "Wayland display: wayland-pickle-rdp-live" || die "Wrong Android Wayland display."
echo "SETUP_COMPLETE. RDP: $ADDRESS:$PORT; username: $RDP_USER. Read password with: sudo cat $CFG/first-login.txt"
