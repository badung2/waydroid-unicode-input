# Waydroid Unicode Input

**Secure Windows Remote Desktop access to Waydroid Android, with Korean/Unicode keyboard composition, per-server username/password (NLA) authentication, and prebuilt ARM64 Weston binaries.**

[🇰🇷 한국어 전체 사용 설명서](README.ko.md) · [Licenses & attribution](NOTICE.md) · [Security](SECURITY.md) · [Detailed troubleshooting](docs/TROUBLESHOOTING.en.md)

> **This project ships:** patched Weston source (as a patch against official Weston 16.0.2), precompiled ARM64 Weston, custom PickleIME Android APK and Java source, a Python RDP→Android keyboard relay, deployment/verification scripts.
>
> **This project does not ship:** Waydroid, Android OS/system/vendor images, GApps, passwords, NLA hashes, TLS private keys, SSH keys, or APK signing private keys.
>
> **Binary target:** Ubuntu **26.04.1 LTS / ARM64 (aarch64)**, built against Weston 16.0.2 and FreeRDP 3.32.2. The source patch may be rebuilt on other distributions/architectures, but their binaries are **not included or verified**.
>
> **Verification status:** Earlier production integration passed 14/14 real Android editor cases and 4/4 post-cutover cases. This public source patch was dry-run verified against an unmodified official Weston 16.0.2 tarball, and the released ARM64 binary was independently compiled and verified to report `weston 16.0.2`. **A complete install-from-zero test on a fresh VM has not been performed yet.**

## 1. Why does this exist?

Waydroid hosts Android in a Linux container. On a headless remote Linux server, it needs a Wayland compositor to present that Android UI over Remote Desktop. Standard Weston RDP does not, by itself, provide the complete Windows Korean/Unicode→Android text-composition pipeline used here.

This project combines a modified Weston 16.0.2 RDP backend, libhangul's Korean two-beolsik composition, an Android `InputMethodService` named PickleIME, and a small ADB relay. It also provisions Weston RDP NLA/NTLM credentials and a TLS certificate.

```text
Windows 11 mstsc (or compatible RDP client)
  │ Private network / Tailscale, TCP 3389, TLS + NLA
  ▼
Patched Weston 16.0.2 RDP
  │ RDP UnicodeKeyboardEvent or scan codes + libhangul
  ▼
Python bridge (ADB reconnect/retry)
  │ Android input broadcasts
  ▼
Custom PickleIME
  ▼
Actual Waydroid Android 13 app text field
```

**Important:** The RDP server is **Weston**, not Waydroid itself. Waydroid displays its Android UI on the Wayland compositor. The client sends keyboard events to Weston, which forwards text to Android through the relay. This is a **general Unicode text transport**, not a Korean-only keyboard; Korean two-beolsik composition is an additional feature. The original `PickleIME`, `com.badung.pickleime`, and `pickle-*` runtime identifiers remain for binary compatibility. Unicode behavior depends on client input events, Android editor support, and character/message limits; not every language, emoji sequence, or app has been end-to-end verified.

## 2. Platform, prerequisites, and network safety

| Requirement | What to prepare |
| --- | --- |
| Linux server | Ubuntu **26.04.1 LTS / ARM64**, network access, normal user with sudo |
| Kernel | Binder driver and binderfs support (e.g. Oracle ARM kernel) |
| Waydroid | Installed and initialized separately (Android image is not in this repository) |
| Network | A private IPv4/Tailscale IP **assigned on the server** |
| Client | Windows `mstsc` or compatible RDP client |
| Resources | Sufficient RAM; headless CPU software rendering may be slower than GPU |

Never expose RDP TCP 3389 or Android ADB port 5555 publicly. Bind RDP to a Tailnet or private address and restrict access at the firewall.

## 3. What's included?

| Path | Purpose |
| --- | --- |
| `source/weston-16.0.2-pickle.patch` | Full source patch against official Weston 16.0.2 |
| `source/android-ime/app/` | Java IME code, Android manifest and XML |
| `dist/weston-arm64.tar.xz` | **Prebuilt** ARM64 Weston for fixed prefix `/opt/pickle-waydroid-rdp/weston` |
| `dist/pickle-ime.apk` | Pre-signed PickleIME Android application (no private key bundled) |
| `runtime/android_input.py` | RDP text/preedit/key message relay, ADB reconnection, self-test |
| `scripts/install.sh` | Install Weston, generate new credentials, enable systemd, install APK |
| `scripts/prepare-binder.sh` | Binder module and binderfs setup before Waydroid container |
| `scripts/verify.sh` | Status/IME/display verification |
| `CHECKSUMS.sha256` | Published artifact integrity |
| `NOTICE.md`, `licenses/` | Third-party attribution and license details |

**Not included:** prior deployment IPs, NLA password hashes, user passwords, previous server TLS keys, APK-signing secrets, home-server credentials, or OS images.

## 4. Prepare a fresh ARM64 Ubuntu server

SSH into the target Linux instance as a **regular user who can sudo**. Confirm:

```bash
uname -m                        # Must print aarch64
cat /etc/os-release              # Ubuntu 26.04.x
uname -r
modinfo binder_linux             # Driver module must be available where modular
```

On some kernels Binder may be built into the kernel instead of a module. If this command fails, check kernel Binder support before proceeding; the installer cannot add a missing kernel driver.

Install required Ubuntu dependencies:

```bash
sudo apt update
sudo apt install -y curl ca-certificates git adb python3 openssl \
  weston libhangul1 libfreerdp-server3-3 libwinpr3-3 pipewire pipewire-pulse
```

The installer does not overwrite your distribution's default Weston package; it uses its own installation prefix.

## 5. Install Waydroid separately and initialize Android

Follow the [official Waydroid Linux installation guide](https://docs.waydro.id/usage/install-on-desktops). Check whether your Ubuntu release already offers the package:

```bash
apt-cache policy waydroid
sudo apt install -y waydroid
```

If it is unavailable, use the **official Waydroid repository** only if it supports your Ubuntu release; do not blindly substitute a different distro's codename. Then initialize the Android system image:

```bash
sudo waydroid init                 # VANILLA, without Google apps
# or optionally: sudo waydroid init -s GAPPS
```

These commands obtain Android images from their normal distribution sources. No Android system/vendor image is embedded in this project.

For headless, GPU-less compute instances: if the Android display is black or fails to start, the Waydroid config `/var/lib/waydroid/waydroid.cfg` may need software rendering. Under its `[properties]` section, depending on your image:

```ini
[properties]
ro.hardware.gralloc = default
ro.hardware.egl = swiftshader
```

Only change this when needed, and restart Waydroid safely afterwards. Without GPU hardware, expect CPU-dependent rendering performance.

## 6. Configure private connectivity

Use Tailscale (see [official Tailscale installation](https://tailscale.com/kb/1031/install-linux)) or an existing private network. Determine the server's bound IP:

```bash
tailscale ip -4                 # If Tailscale is installed and active
ip -br addr                    # Show all addresses
```

Use an IPv4 address already assigned to the server. Don't set an Internet-facing public IP. Avoid a broad OCI NSG/security-list ingress rule that opens port 3389 to the world.

## 7. Download and validate this release

Clone the GitHub repository (or download the published ZIP):

```bash
git clone https://github.com/badung2/waydroid-unicode-input.git
cd waydroid-unicode-input
bash scripts/install.sh --check
```

A correct preflight prints `CHECK_OK`, after validating supported architecture, OS, and SHA-256 checksums. This check **does not install anything**.

You can independently check:

```bash
sha256sum -c CHECKSUMS.sha256
```

**No rebuilding is necessary** for the supported Ubuntu ARM64 target.

## 8. Install the prebuilt Weston, Android IME and services

Run from the same normal user account that will run Waydroid. Use `sudo`, not a bare root login.

```bash
sudo bash scripts/install.sh --bind YOUR_PRIVATE_IP --user pickle --port 3389
```

If `waydroid status` reports an Android IP different from `192.168.240.112`, append `--android-ip ACTUAL_ANDROID_IP`.

The installer:

1. Verifies architecture, Ubuntu version, checksums, runtime dependencies, and local bind address.
2. Installs the prebuilt Weston under `/opt/pickle-waydroid-rdp/weston`.
3. Generates a **new** NLA user password and NTLM hash plus **new** TLS certificate/private key **for this server only**.
4. Installs the Binderfs preparation script and a Waydroid systemd override.
5. Enables persistent per-user Weston, Waydroid UI, and Python IME relay units.
6. Waits for Android boot over local ADB, installs PickleIME, enables it, and starts the relay.

The installer never copies your original OCI credentials to another region.

### Find the new username and password

```bash
sudo cat /etc/pickle-waydroid-rdp/first-login.txt
```

This file is readable by root only. Store it in a trusted password manager, never commit or share it, and optionally delete it when no longer needed.

## 9. Connect from Windows 11

1. Press `Win + R`, run `mstsc`.
2. Computer: `YOUR_PRIVATE_IP:3389`.
3. Username: the `--user` value (default: `pickle`).
4. Password: freshly generated by the installer.
5. On the first connection, verify the server's self-signed TLS certificate fingerprint:

```bash
openssl x509 -in /etc/pickle-waydroid-rdp/tls.crt -noout -fingerprint -sha256
```

Whether Windows remembers your credentials is controlled by the Windows **client** credential policies, not by the Linux installer. Always keep the Tailnet/private network restricted to trusted devices.

## 10. Keyboard usage

| Action | How |
| --- | --- |
| English letters | Default scan-code mode |
| Korean on/off | **Shift + Space** |
| Physical Korean toggle key | Works only if the RDP client forwards the corresponding key events |
| Korean composition | Host libhangul two-beolsik (`ㅎ → 하 → 한`) |
| Unicode commits | Forwarded for clients that send `UnicodeKeyboardEvent` |
| Backspace, Tab, arrow keys, Enter | Serialized Android input events |

Test `안녕하세요 반갑습니다.`, `Hello 2026!`, punctuation, Backspace, multiline text and cursor movement in an Android text field. RDP clients and Android apps can handle text input differently; some combinations require additional testing.

## 11. Verify the actual running services

```bash
bash scripts/verify.sh
sudo waydroid shell wm size
sudo waydroid shell wm density
sudo waydroid shell settings get secure default_input_method
```

Expected: three user services show `enabled` and `active`; Waydroid Session/Container are `RUNNING`; default display is `1280x800` landscape and density is approximately `180`; IME is `com.badung.pickleime/.PickleIME`. Additionally, log in by RDP and type Korean into a real Android text field.

For logs:

```bash
systemctl --user status pickle-rdp-live.service
systemctl --user status pickle-waydroid-live.service
systemctl --user status pickle-rdp-android-input.service
journalctl --user -u pickle-rdp-android-input.service -n 50 --no-pager
systemctl status waydroid-container.service
adb devices
```

`RDP_ANDROID_IME_READY` means the relay finished its initialization; **it does not prove** a specific third-party Android app accepted typing. Verify that directly.

## 12. Verify persistence across reboots

The installer uses `systemctl --user enable` and `loginctl enable-linger` for user service startup, and a system service override to create Binderfs devices before Waydroid starts.

```bash
loginctl show-user "$USER" -p Linger
systemctl --user is-enabled pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service
```

When it is safe to restart your server, reboot and rerun `bash scripts/verify.sh`. The relay reconnects ADB automatically when a disconnected device becomes available.

## 13. Troubleshooting at a glance

| Symptom | What to check |
| --- | --- |
| RDP connection refused | `ss -ltn \| grep 3389`, bind address, private network, Weston unit |
| NLA login fails | New username/password, permission of `users.sam`, correct bind/IP, TLS |
| Android screen blank | Waydroid status, socket, software renderer on GPU-less instance |
| Waydroid fails after reboot | `journalctl -u waydroid-container`, binderfs, Binder kernel module |
| English works; Korean does not | Shift+Space, PickleIME selected, relay service and logs |
| Korean fails after a disconnect | `adb devices`, relay retry logs, restart the relay |
| Wrong layout/resolution | Weston `--width`/`--height`, Android `wm size` and density |
| Android IP differs | Use the actual `waydroid status` IP and `--android-ip` |
| Windows forgets saved credentials | Windows `cmdkey /list` and local credential-saving policy |

Do not stop unrelated Docker applications or other system services while troubleshooting.

## 14. Optional: rebuild from upstream Weston source

The prebuilt release requires **no compilation**. If you need to rebuild or port to another distro/architecture:

```bash
curl -L -O https://gitlab.freedesktop.org/wayland/weston/-/releases/16.0.2/downloads/weston-16.0.2.tar.xz
echo '49dd87d18cb229384264d2f69cb5a51f14f61a111e9227bfedb91b3ca8c39643  weston-16.0.2.tar.xz' | sha256sum -c -
tar xf weston-16.0.2.tar.xz
patch -d weston-16.0.2 -p2 < source/weston-16.0.2-pickle.patch
```

The patch transforms the official Weston source; the original archive is intentionally **not** bundled. Java IME sources are in `source/android-ime/app/`; the text relay is `runtime/android_input.py`. APK private signing keys are **never distributed**. Rebuilding the APK requires a new signing key.

## 15. Attribution, limitations, and license

Modified Weston remains subject to its upstream copyright/license, documented in [licenses/WESTON-MIT.txt](licenses/WESTON-MIT.txt). libhangul is provided through the operating system under LGPL-2.1+ and other notices; see [NOTICE.md](NOTICE.md) and [licenses/LIBHANGUL-COPYRIGHT.txt](licenses/LIBHANGUL-COPYRIGHT.txt).

This is an independent community project, **not an official release of Weston, Waydroid, Microsoft, Oracle, or Tailscale**. Complete fresh-VM installation, alternative Android versions, and all possible client/input combinations have not yet been verified.
