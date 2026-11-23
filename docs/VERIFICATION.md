# Verification status / 검증 기록

## Verified on 2026-11-22 (OCI Tokyo, Ubuntu 26.04.1 ARM64)

- Official Weston 16.0.2 tarball SHA-256 matched and patched successfully (`patch --dry-run` clean).
- Independent release binary build succeeded; `weston --version` reported `16.0.2`, RDP plugin present.
- Public artifact hashes and the input-relay self-test passed.
- Preflight `bash scripts/install.sh --check`: **PASS**.
- Isolated test account `pickle-smoke-rdp`, RDP listening on localhost TCP **3397**: **PASS** after fixing directory ownership and executable-prefix permissions.
- Three **NLA authentication** scenarios: valid username/password accepted, incorrect password rejected, TLS-only bypass rejected: **3/3 PASS**.
- Actual RDP client → newly built Weston (port 3397) → Android PickleIME editor: **4/4 PASS** (`period`, `multiline`, `backspace_retype`, `toggle_latin`).
- Android package verification setting was temporarily changed for installing test-only editor APK, then **restored**; the prior values of `verifier_verify_adb_installs` and `package_verifier_enable` were both `null` before/after.
- Existing production Waydroid session and all three production RDP/Android services remained active during tests.

## Limits / 아직 미검증

- A completely blank **second OCI VM** has not undergone Waydroid OS download, Android first boot, or host reboot.
- The isolated RDP test **reused the existing Android session**; a second Waydroid GUI session under a different Linux user returned `RuntimeError: Already tracking a session`. A clean host is required for the end-to-end installer test.
- The installer has **not** completed `SETUP_COMPLETE` end-to-end on a separate fresh VM; don't claim full new-instance certification.
- Direct Windows `mstsc` interaction with the **isolated** port 3397 was not tested (headless FreeRDP was used).

## Fixes found through literal README-driven deployment

1. `~/.config/systemd` root-owned parents made units unreadable; installer now creates parents with target user ownership.
2. `/opt/pickle-waydroid-rdp` mode 0700 caused `weston` `203/EXEC`; installer now uses mode 0755.
3. Archive extraction initially placed binaries one level too high; installer now extracts beneath `/opt/pickle-waydroid-rdp/weston`.
4. `libhangul1` may not be installed by default; the README includes `apt install libhangul1`.
5. Android package verifier delayed ADB APK installation on the existing GAPPS image; installer now times out with actionable diagnostics rather than hanging indefinitely.
6. Already-running Waydroid session from another user is now detected **before** modifying a host.

## Goal-oriented criteria before declaring full release

- Empty Ubuntu 26.04 ARM64 VM, Waydroid initialized independently.
- `sudo bash scripts/install.sh ...` exits 0 and prints `SETUP_COMPLETE`.
- Correct NLA login succeeds; wrong password and TLS bypass fail.
- UI is 1280x800; Korean/Unicode editing works on Windows and via FreeRDP.
- Reboot preserves Binder, Weston, Android session, IME selection and Korean input.
- Public archive contains no actual credentials, host private keys or Android images.

Result: **Isolated RDP/IME functional test verified. Complete clean-VM install still pending.**