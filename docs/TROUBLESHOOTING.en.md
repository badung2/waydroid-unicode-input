# Troubleshooting · 문제 해결

For the full installation instructions, read the [English README](../README.md) first.

## RDP connection refused

```bash
systemctl --user status pickle-rdp-live.service
journalctl --user -u pickle-rdp-live.service -n 60 --no-pager
ss -lnt | grep ':3389'
sudo namei -l /opt/pickle-waydroid-rdp/weston/bin/weston
```

An `ExecStart status=203/EXEC` may indicate inaccessible executable or parent directories. Release binaries must be traversable by the user; credential files stay private.

## User systemd unit not found

```bash
namei -l ~/.config/systemd/user
systemctl --user daemon-reload
systemctl --user list-unit-files | grep pickle
```

Root-owned mode-700 `~/.config` parents can block a new user's access to unit files. The installer creates those directories under the intended user account.

## Waydroid `Already tracking a session`

A second user cannot launch another Waydroid UI session while the container already has a tracked session. On a fresh host, run Waydroid under one ordinary user account. Do not kill existing sessions on a shared server just to retry an installer.

## Binder / Android startup

```bash
systemctl status waydroid-container.service
journalctl -u waydroid-container.service -n 60 --no-pager
ls -l /dev/binderfs /dev/binder
modinfo binder_linux
```

If your kernel lacks Binder, the installer cannot supply that missing driver. GPU-less hosts may need Waydroid SwiftShader settings.

## NLA login and certificate

```bash
sudo cat /etc/pickle-waydroid-rdp/first-login.txt
sudo openssl x509 -in /etc/pickle-waydroid-rdp/tls.crt -noout -fingerprint -sha256
```

RDP credentials are different from Linux/SSH login. Verify certificate fingerprints on initial connection and never expose RDP TCP 3389 publicly.

## No Korean text

```bash
adb devices
sudo waydroid shell settings get secure default_input_method
systemctl --user status pickle-rdp-android-input.service
journalctl --user -u pickle-rdp-android-input.service -n 40 --no-pager
```

IME must be `com.badung.pickleime/.PickleIME`. Toggle Hangul using `Shift + Space`, then type Korean, punctuation, Backspace and Enter in a real Android text field.

## Reboot verification

```bash
loginctl show-user "$USER" -p Linger
systemctl --user is-enabled pickle-rdp-live pickle-waydroid-live pickle-rdp-android-input
bash scripts/verify.sh
```

Before rebooting a production host, record running service state and a rollback method.

See [verification status](VERIFICATION.md) for independently completed tests.