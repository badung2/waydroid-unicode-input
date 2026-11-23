# Waydroid Unicode Input

**Waydroid의 Android 화면에 Windows 원격 데스크톱(RDP)으로 접속하고, 한글·유니코드 입력과 아이디/비밀번호(NLA) 로그인을 사용할 수 있게 하는 오픈소스 패치 패키지.**

[English README](README.md) · [라이선스/출처](NOTICE.md) · [보안](SECURITY.md) · [고급 문제 해결](docs/TROUBLESHOOTING.ko.md)

> **배포 범위:** Weston 패치 소스, 한글 입력 브리지, PickleIME Android 앱 소스·APK, 검증된 ARM64용 Weston 빌드, 설정·검증 스크립트. **Waydroid 프로그램·Android 운영체제 이미지·Google 앱은 포함하지 않아.**
>
> **호환성:** 사전 빌드한 바이너리는 **Ubuntu 26.04.1 LTS / ARM64(aarch64)**용이야. Waydroid 1.6.3 / Android 13, Weston 16.0.2 / FreeRDP 3.32.2 기반에서 제작했어. 다른 환경은 패치를 적용한 후 별도로 빌드해야 할 수 있어.
>
> **검증 범위:** 기존 OCI 서버에서는 Android 입력 테스트 14/14, 운영 전환 검증 4/4가 통과했어. 공개용 패치를 공식 Weston 원본에 적용하는 시험과 공개용 바이너리의 빌드·버전 확인은 했지만, **완전히 새로운 빈 VM에서 설치 스크립트를 처음부터 끝까지 검증한 건 아니야.**

## 1. 어떤 문제를 해결하나?

Waydroid 자체는 Android를 Linux에서 실행하는 도구야. 그런데 GUI가 없는 원격 Linux 서버의 Android를 Windows RDP로 쓰려면 별도의 Wayland 화면 서버가 필요해.

일반 Weston RDP만으로는 Windows의 유니코드/한글 조합 입력을 Android 앱까지 온전히 전달하기 어려웠어. 이번 패키지는 RDP 키 이벤트를 처리하는 Weston 16.0.2를 수정하고, libhangul + 자체 Android 입력기(PickleIME)와 Python 브리지를 더해 이 경로를 연결해. 동시에 사용자 이름과 비밀번호를 쓰는 NLA/NTLM 인증을 설정해.

```text
Windows 11 (mstsc) 또는 기타 RDP 클라이언트
    │ 사설망/Tailscale :3389 · TLS + NLA
    ▼
패치된 Weston 16.0.2 RDP 서버
    │ UnicodeKeyboardEvent 또는 scan code · libhangul 두벌식 조합
    ▼
Python 입력 브리지 (ADB 재연결 포함)
    │ Android 입력 이벤트
    ▼
PickleIME (Android InputMethodService)
    ▼
Waydroid Android 13의 실제 입력창
```

여기서 **RDP 서버는 Waydroid가 아니라 Weston**이고, Android는 Weston의 Wayland 화면 위에 출력돼. **한글 전용이 아닌 범용 유니코드 텍스트 전달 기능**이며, 한글 두벌식 조합은 추가 기능이야. `PickleIME`, `com.badung.pickleime`, `pickle-*` 같은 기존 런타임 식별자는 바이너리 호환성을 위해 유지했어. 실제 지원 범위는 RDP 클라이언트, Android 입력창, 문자·메시지 길이에 따라 달라지며 모든 문자와 앱의 종단 간 동작을 보장하지 않아.

## 2. 설치 전 준비물

| 구분 | 준비할 것 |
| --- | --- |
| 새 서버 | Ubuntu **26.04.1** ARM64, sudo 가능한 일반 사용자, 네트워크 연결 |
| 커널 | binder_linux 모듈 및 binderfs를 쓸 수 있는 커널 |
| Android | Waydroid 설치 및 이미지 초기화(별도 다운로드) |
| 접속 | Tailscale 또는 다른 사설망, 서버의 사설 IPv4 주소 |
| Windows | 내장 원격 데스크톱 연결 프로그램 `mstsc` |
| 권장 | RAM 8GB 이상, 그래픽 가속이 없는 경우 CPU 여유 |

**공인 IP의 TCP 3389와 Android ADB 5555를 인터넷에 직접 개방하지 마.** 새 OCI 리전에서는 Tailscale IP를 쓰는 게 편하고 안전해.

### 설치에 포함된 파일

| 폴더/파일 | 용도 |
| --- | --- |
| `source/weston-16.0.2-pickle.patch` | 공식 Weston 16.0.2 소스에 적용하는 수정 패치 |
| `source/android-ime/app/` | 직접 제작한 Android 입력기 Java·Manifest 원본 |
| `dist/weston-arm64.tar.xz` | **빌드 없이** 사용하는 ARM64 Weston 바이너리 |
| `dist/pickle-ime.apk` | Android에 설치할 PickleIME APK |
| `runtime/android_input.py` | RDP/ADB ↔ Android IME 입력 이벤트 중계 |
| `scripts/install.sh` | 새 서버용 설치, 자격증명 생성, systemd 자동시작 구성 |
| `scripts/prepare-binder.sh` | 재부팅 때 Waydroid Binder 장치 준비 |
| `scripts/verify.sh` | 서비스·Android·화면·IME 상태 점검 |
| `CHECKSUMS.sha256` | 빌드파일·패치·APK 무결성 확인 |
| `NOTICE.md`, `licenses/` | 서드파티 출처 및 라이선스 |

**절대 포함하지 않는 파일:** 운영 서버 계정 비밀번호, NTLM 해시(`users.sam`), TLS 개인키, `credentials.json`, 서명용 개인키, SSH 키, 기존 서버의 사설 IP/로그.

## 3. 새 Ubuntu ARM64 서버 준비

SSH로 서버에 접속한 뒤 아래를 실행해.

```bash
uname -m          # aarch64
cat /etc/os-release
uname -r
modinfo binder_linux
```

`aarch64`가 아니거나 지원되지 않는 Ubuntu 버전이면 **사전 빌드 바이너리를 설치하면 안 돼.** `modinfo binder_linux`가 실패하면 해당 커널에서 Binder를 사용할 수 있는지 먼저 해결해야 해. 커널에 따라 모듈 대신 내장 방식일 수도 있으니 Binder 지원 여부를 추가 확인해.

기본 패키지:

```bash
sudo apt update
sudo apt install -y curl ca-certificates git adb python3 openssl \
  weston libhangul1 libfreerdp-server3-3 libwinpr3-3 pipewire pipewire-pulse
```

설치 도중 `Unable to locate package`가 나온다면 저장소 구성과 Ubuntu 버전을 확인해. 시스템의 기존 그래픽 세션을 없애거나 다른 Weston 설치를 덮어쓸 필요는 없어.

## 4. Waydroid 설치와 Android 초기화 (별도)

Waydroid는 이번 배포물에 포함돼 있지 않아. [Waydroid 공식 설치 안내](https://docs.waydro.id/usage/install-on-desktops)를 기준으로 설치해. Ubuntu의 기본 저장소에서 설치가 가능하면 아래처럼 해.

```bash
apt-cache policy waydroid
sudo apt install -y waydroid
```

패키지가 없다면 공식 Waydroid 저장소의 **해당 Ubuntu 버전 지원 여부**를 먼저 확인하고 [공식 설치 안내](https://docs.waydro.id/usage/install-on-desktops)에 따라 저장소를 추가해야 해. 임의의 Ubuntu 코드명을 강제로 지정하지 마.

최초 한 번 Android 이미지를 초기화해.

```bash
sudo waydroid init            # Google 앱 없는 VANILLA 이미지
# 또는 (선택 사항): sudo waydroid init -s GAPPS
```

위 과정은 Android 시스템/벤더 이미지를 **Waydroid 공급처에서 다운로드**하는 단계야. 다운로드한 이미지는 이 GitHub 저장소에 올라가지 않아.

**GPU 없는 OCI 인스턴스:** Android 화면이 검게 나오거나 세션이 실행되지 않으면 `/var/lib/waydroid/waydroid.cfg`의 `[properties]` 아래 소프트웨어 렌더링 속성을 지정해야 할 수 있어.

```ini
[properties]
ro.hardware.gralloc = default
ro.hardware.egl = swiftshader
```

이미 정상 동작하는 서버에서는 변경하지 마. GPU가 없으면 CPU 렌더링이므로 부드러움은 CPU 성능에 따라 달라져.

## 5. Tailscale 또는 사설망 준비

새 서버에서 Tailscale을 사용한다면 [Tailscale 공식 설치 가이드](https://tailscale.com/kb/1031/install-linux)를 참고해 설치·인증하고, 아래 명령으로 IP를 확인해.

```bash
tailscale ip -4
ip -br addr
```

이후 예제에서 `YOUR_PRIVATE_IP`를 **실제 서버에 할당된 사설 IP 또는 Tailscale IP**로 바꾸면 돼. 공인 IP를 지정하지 마.

OCI 보안 목록/NSG와 서버 방화벽에도 공용 3389 허용 규칙을 만들지 말고, Tailnet 내부 접근만 허용해.

## 6. 공개 파일 다운로드 및 검증

GitHub에서 이 프로젝트를 clone하거나 ZIP으로 받아 압축 해제한 뒤 프로젝트 폴더에 들어가.

```bash
git clone https://github.com/badung2/waydroid-unicode-input.git
cd waydroid-unicode-input
bash scripts/install.sh --check
```

`CHECK_OK`가 나오면 CPU/운영체제/파일 해시 검사를 통과한 거야. 이 단계는 서비스를 설치하지 않아.

검증 명령을 따로 실행해도 돼.

```bash
sha256sum -c CHECKSUMS.sha256
```

**빌드 과정은 필요 없어.** `dist/weston-arm64.tar.xz`와 `dist/pickle-ime.apk`가 이미 들어 있어.

## 7. 설치 실행

이 명령은 **Waydroid를 사용하는 일반 Linux 사용자 계정에서 sudo로** 실행해. `root` 셸만 사용하는 방식은 권장하지 않아.

```bash
sudo bash scripts/install.sh --bind YOUR_PRIVATE_IP --user pickle --port 3389
```

서버의 Waydroid IP가 기본값 `192.168.240.112`와 다르면 `waydroid status`에서 주소를 확인하고 `--android-ip 실제_IP`를 추가해.

설치 스크립트는 새 서버에 다음을 구성해.

1. CPU·Ubuntu 버전과 패키지 체크섬 검증
2. 패치된 Weston 바이너리를 `/opt/pickle-waydroid-rdp/weston`에 설치
3. **새로운** RDP 사용자/NLA 해시/TLS 키·인증서 생성
4. Waydroid Binderfs 장치 준비와 재부팅 후 systemd 연계
5. 화면 서버, Android UI, 한글 브리지의 사용자 systemd 서비스 등록 및 자동 시작
6. Android 부팅을 확인한 다음 PickleIME APK 설치·활성화

기존 OCI 서버의 계정·TLS 키를 복사하는 과정은 없어.

### 최초 로그인 정보

```bash
sudo cat /etc/pickle-waydroid-rdp/first-login.txt
```

**이 파일은 현재 서버에서 새로 발급한 비밀번호를 담으므로 타인에게 공유하거나 GitHub에 올리면 안 돼.** 안전한 비밀번호 관리 도구에 옮긴 후 삭제해도 돼. 다른 서버에 같은 설정을 설치하면 비밀번호·인증서는 별도로 생성돼.

## 8. Windows 11에서 접속

1. Windows에서 `Win + R` → `mstsc` 실행
2. 컴퓨터: `YOUR_PRIVATE_IP:3389`
3. 사용자 이름: 설치 때 `--user`에 지정한 값(기본 `pickle`)
4. 비밀번호: `first-login.txt`에 저장된 새 비밀번호
5. 처음 연결할 때 자체 서명 인증서 안내가 나오면 **연결하려는 서버의 인증서 지문을 직접 확인**한 다음 진행

`/etc/pickle-waydroid-rdp/tls.crt`에서 지문을 확인할 수 있어.

```bash
openssl x509 -in /etc/pickle-waydroid-rdp/tls.crt -noout -fingerprint -sha256
```

Windows의 `자격 증명 기억` 여부는 **Windows 클라이언트 정책**에 달려 있으며, 이 서버 설치 스크립트가 강제하지 않아.

## 9. 한글/영문 입력 방법

| 동작 | 방법 |
| --- | --- |
| 영어 입력 | 기본 스캔코드 입력 모드 |
| 한글 전환 | **Shift + Space** |
| 한국어 물리 한/영 키 | 클라이언트가 키 이벤트를 전달하는 경우에 한해 지원 가능 |
| 한글 조합 | `libhangul` 두벌식(`ㅎ → 하 → 한`) |
| 유니코드 입력 | RDP 클라이언트가 UnicodeKeyboardEvent를 전달하면 직접 전달 |
| Backspace/방향키/Enter | Android IME 입력 이벤트로 처리 |

입력창에 `안녕하세요 반갑습니다.`, `Hello 2026!`, 특수기호, 여러 줄 입력을 시도해 봐. **클라이언트·Android 앱에 따라 입력 이벤트 동작이 다를 수 있어.**

## 10. 설치 후 점검

```bash
bash scripts/verify.sh
sudo waydroid shell wm size
sudo waydroid shell wm density
sudo waydroid shell settings get secure default_input_method
```

정상 기준: Weston/Waydroid/입력 브리지 3개 서비스가 모두 `active`·`enabled`, Waydroid Session/Container `RUNNING`, 화면은 기본 `1280x800` 가로, IME는 `com.badung.pickleime/.PickleIME`, RDP 접속 및 한글 입력 성공.

로그:

```bash
systemctl --user status pickle-rdp-live.service
systemctl --user status pickle-waydroid-live.service
systemctl --user status pickle-rdp-android-input.service
journalctl --user -u pickle-rdp-android-input.service -n 50 --no-pager
systemctl status waydroid-container.service
adb devices
```

`RDP_ANDROID_IME_READY`가 보이면 브리지 시작 준비를 통과한 거야. 실제 앱 입력까지 성공했다는 뜻은 아니니 직접 타이핑 시험도 해.

## 11. 재부팅·자동 복구

설치 시 `systemctl --user enable`과 `loginctl enable-linger`로 서비스 자동 시작을 구성해. Linux 시스템 부팅 시 Waydroid Binderfs를 먼저 준비하도록 설정해.

```bash
loginctl show-user "$USER" -p Linger
systemctl --user is-enabled pickle-rdp-live.service pickle-waydroid-live.service pickle-rdp-android-input.service
```

재부팅 자체가 안전한 환경인지 확인한 후에만 재시작 테스트를 진행해. 새 서버에서는 부팅 뒤 `bash scripts/verify.sh`를 재실행해. 입력 브리지는 ADB 연결이 끊기면 재접속을 시도하도록 구현했어.

## 12. 주요 오류 해결

| 증상 | 검사할 것 |
| --- | --- |
| 연결이 거부됨 | `ss -ltn | grep 3389`, Tailscale/IP 바인딩, 방화벽, Weston 사용자 서비스 |
| NLA 인증 실패 | 서버 내부 `users.sam` 권한, 이름/비밀번호, TLS 설정, 접속 주소 |
| Android 검은 화면 | Wayland 소켓, Waydroid 상태, GPU가 없다면 SwiftShader |
| 부팅 후 Waydroid 실패 | `journalctl -u waydroid-container`, `/dev/binderfs`, Binder 모듈 |
| 영어만 입력됨 | `Shift+Space`, PickleIME 선택 상태, 브리지 서비스 로그 |
| 연결 이후 한글이 사라짐 | `adb devices` 확인, 브리지 재시작 및 자동 재연결 로그 |
| 레이아웃이 너무 작거나 큼 | Weston 서비스의 `--width`, `--height`; Android `wm size`와 DPI 확인 |
| Android IP가 달라짐 | `waydroid status`에서 실제 IP 확인, 설치 옵션 `--android-ip` 일치 여부 |
| Windows 저장 비번이 사라짐 | Windows `cmdkey /list`와 자격 증명 저장 정책 점검 |

문제를 해결하기 전에 운영중인 다른 Docker/서비스를 함부로 중지하지 마.

## 13. 직접 소스 빌드(선택 사항)

이미 빌드된 바이너리를 쓰면 이 단계는 건너뛰어도 돼. 패치 원본 검증·다른 아키텍처 빌드가 필요하면 공식 Weston 16.0.2 소스를 내려받아.

```bash
curl -L -O https://gitlab.freedesktop.org/wayland/weston/-/releases/16.0.2/downloads/weston-16.0.2.tar.xz
echo '49dd87d18cb229384264d2f69cb5a51f14f61a111e9227bfedb91b3ca8c39643  weston-16.0.2.tar.xz' | sha256sum -c -
tar xf weston-16.0.2.tar.xz
patch -d weston-16.0.2 -p2 < source/weston-16.0.2-pickle.patch
```

IME 원본은 `source/android-ime/app/`, 브리지 코드는 `runtime/android_input.py`에 있어. **APK 서명용 개인키는 배포하지 않으므로** 직접 재빌드한 APK에 서명하려면 새로운 키가 필요해.

## 14. 프로젝트 출처·제약

이건 Weston/Waydroid의 공식 릴리스가 아니라, **Weston 16.0.2를 기반으로 수정한 커뮤니티 배포본**이야. Weston의 기존 저작권 고지를 유지하고, libhangul은 LGPL-2.1+ 등 별도 라이선스를 사용해. [NOTICE.md](NOTICE.md)와 [licenses/](licenses/)를 꼭 읽어 줘.

다른 배포판·RDP 클라이언트·Android 앱에서 같은 동작이 자동 보장되는 건 아니야. 특히 새 VM 완전 설치·재부팅 테스트는 후속 검증 항목이야.
