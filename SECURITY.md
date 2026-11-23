# Security / 보안

- **Do not expose TCP 3389 to the public Internet.** Use a private/Tailscale/WireGuard address and firewall.
- Installation generates new NLA credentials and a self-signed TLS certificate *on each server*. The generated password is kept at `/etc/pickle-waydroid-rdp/first-login.txt` (root only); read and securely store it, then optionally delete it.
- Never commit `users.sam`, `tls.key`, certificates from an actual deployment, `credentials.json`, SSH keys, private APK signing keys, personal IPs, or logs.
- The prebuilt APK accepts input broadcasts from the installed local relay. Treat devices with local ADB access as trusted. Do not publicly expose ADB port 5555.
- The prebuilt Weston binary targets **Ubuntu 26.04 / ARM64**. Use source patches and rebuild for other distributions/architectures.
- Before publishing a fork, run a fresh secret scan and verify checksums.
- Security-sensitive RDP authentication can change between Weston/FreeRDP versions; avoid replacing library versions without testing good/bad NLA credentials.
