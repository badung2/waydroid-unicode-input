# 문제 해결 · Troubleshooting

완전한 설치·사용 설명서는 [한국어 README](../README.ko.md)를 먼저 읽어 줘.

## 1. RDP 연결 거부

```bash
systemctl --user status pickle-rdp-live.service
journalctl --user -u pickle-rdp-live.service -n 60 --no-pager
ss -lnt | grep ':3389'
sudo namei -l /opt/pickle-waydroid-rdp/weston/bin/weston
```

상위 폴더 접근 권한이 막혔다면 `status=203/EXEC`가 나올 수 있어. 실행 폴더는 일반 사용자도 접근할 수 있어야 하고, 인증키 디렉터리는 제한 권한으로 유지해야 해.

## 2. systemd 서비스가 없다는 오류

```bash
namei -l ~/.config/systemd/user
systemctl --user daemon-reload
systemctl --user list-unit-files | grep pickle
```

신규 사용자에서 `~/.config/systemd`를 root 소유 권한 700으로 만들면 본인 계정조차 서비스 파일을 읽지 못해. 설치 스크립트에는 이 문제를 수정해 뒀어.

## 3. Waydroid `Already tracking a session`

한 호스트에 이미 Waydroid 세션이 있다면 두 번째 사용자로 `waydroid show-full-ui`를 시작할 수 없어. 테스트 중 기존 실행 중인 Android를 무작정 중지하지 마. 신규 서버에서는 한 명의 일반 사용자가 소유하도록 실행해.

## 4. Binder·부팅 문제

```bash
systemctl status waydroid-container.service
journalctl -u waydroid-container.service -n 60 --no-pager
ls -l /dev/binderfs /dev/binder
modinfo binder_linux
```

Binder 커널 모듈이 없다면 단순 설치 스크립트로 해결할 수 없어. GPU 없는 서버에서는 Waydroid의 SwiftShader 설정이 필요할 수 있어.

## 5. 아이디/비밀번호 로그인 문제

```bash
sudo cat /etc/pickle-waydroid-rdp/first-login.txt
sudo openssl x509 -in /etc/pickle-waydroid-rdp/tls.crt -noout -fingerprint -sha256
```

RDP NLA 비밀번호는 Linux SSH 비밀번호와 별개야. 처음 접속하면 인증서 지문을 확인해. TCP/3389를 공인 인터넷에 열지 마.

## 6. 한글 입력이 안 될 때

```bash
adb devices
sudo waydroid shell settings get secure default_input_method
systemctl --user status pickle-rdp-android-input.service
journalctl --user -u pickle-rdp-android-input.service -n 40 --no-pager
```

IME가 `com.badung.pickleime/.PickleIME`여야 해. `Shift + Space`로 한글 모드로 바꿔서 실제 Android 입력창에서 `안녕하세요`, 숫자, 특수문자, Backspace와 Enter를 확인해.

## 7. 재부팅 검증

```bash
loginctl show-user "$USER" -p Linger
systemctl --user is-enabled pickle-rdp-live pickle-waydroid-live pickle-rdp-android-input
bash scripts/verify.sh
```

기존 서비스가 중요한 서버에서는 재부팅 테스트 전에 상태와 복원 방법을 확인해.

검증 범위는 [테스트 기록](VERIFICATION.md)을 참고해.