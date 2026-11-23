# Third-party notices / 외부 프로젝트 출처

- **Weston 16.0.2** (Wayland project): https://gitlab.freedesktop.org/wayland/weston, copyright and MIT/X11-style notices in [licenses/WESTON-MIT.txt](licenses/WESTON-MIT.txt). Release: 2026-10-26. Upstream archive SHA256: `49dd87d18cb229384264d2f69cb5a51f14f61a111e9227bfedb91b3ca8c39643`.
- **libhangul 0.2.0**: https://github.com/libhangul/libhangul, LGPL-2.1+ and BSD components, from Ubuntu packages; binary redistribution is avoided here. Install via `apt install libhangul1` (see [licenses/LIBHANGUL-COPYRIGHT.txt](licenses/LIBHANGUL-COPYRIGHT.txt)).
- **FreeRDP 3.x**: https://github.com/FreeRDP/FreeRDP, required dynamically at runtime and installed by OS package manager, not bundled.
- **WSLg Chinese IME investigation by baiiiii**: https://github.com/baiiiii/wslg-build and https://github.com/microsoft/wslg/issues/9, explored for inspiration around MS-RDPETXT. This release is a separate Weston/Android integration; it does not claim authorship of external projects.
- **Waydroid**: https://waydro.id/, must be installed separately. No Android system, vendor image, Google apps, or Waydroid APKs are included.

The bundled Android IME APK is signed with a development key whose private half is NOT distributed. Future APK updates signed with a different key may require uninstalling the existing APK (which can discard its settings).
