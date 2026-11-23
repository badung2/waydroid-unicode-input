#!/usr/bin/env python3
"""Receive authenticated local Weston text commits and deliver to Android IME."""
import base64
import json
import os
from pathlib import Path
import queue
import signal
import socket
import struct
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parent
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1001"))
ADDRESS = os.environ.get("PICKLE_RDP_ANDROID_SOCKET", str(RUNTIME_DIR / "pickle-rdp-android.sock"))
IME = os.environ.get("PICKLE_ANDROID_IME", "com.android.adbkeyboard/.AdbIME")
ADB = ["adb", "-s", os.environ.get("PICKLE_ANDROID_ADB_TARGET", "192.168.240.112:5555")]
SAVED = RUNTIME_DIR / "pickle-rdp-previous-ime.json"
STOP = threading.Event()
# Windows RDP virtual-key -> Android KeyEvent keycode (for non-text keys).
ANDROID_KEYS = {
    0x0D: 66, 0x09: 61, 0x25: 21, 0x27: 22, 0x26: 19, 0x28: 20,
    0x24: 122, 0x23: 123, 0x2E: 112, 0x21: 92, 0x22: 93, 0x1B: 111,
}

def android(*args):
    p = subprocess.run(ADB + list(args), text=True, capture_output=True, timeout=8)
    if p.returncode:
        # Waydroid's TCP ADB device is not retained across host reboots.
        subprocess.run(["adb", "connect", ADB[2]], text=True,
                       capture_output=True, timeout=8)
        p = subprocess.run(ADB + list(args), text=True, capture_output=True, timeout=8)
    if p.returncode:
        raise RuntimeError("Android command failed: " + args[0] + ": " + p.stderr.strip())
    return p.stdout.strip()

def receive_text(payload):
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not text or len(payload) > 2048 or any(ord(c) < 32 for c in text):
        return None
    return text

def receive_message(payload):
    if payload == b"\x02":
        return ("delete", "", "")
    if payload[:1] == b"\x03":
        if len(payload) != 2 or payload[1] not in ANDROID_KEYS:
            return None
        return ("key", str(ANDROID_KEYS[payload[1]]), "")
    if payload[:1] != b"\x01":
        text = receive_text(payload)
        return ("commit", text, "") if text is not None else None
    if len(payload) < 5 or len(payload) > 2053:
        return None
    committed_len, preedit_len = struct.unpack(">HH", payload[1:5])
    if committed_len + preedit_len != len(payload) - 5:
        return None
    committed = receive_text(payload[5:5 + committed_len]) if committed_len else ""
    preedit = receive_text(payload[5 + committed_len:]) if preedit_len else ""
    if committed is None or preedit is None:
        return None
    return ("state", committed, preedit)

def ensure_ime():
    existing = android("shell", "settings", "get", "secure", "default_input_method")
    if not existing or existing == "null":
        raise RuntimeError("Unknown original Android keyboard")
    if not SAVED.exists():
        SAVED.write_text(json.dumps({"previous": existing}), encoding="utf-8")
        SAVED.chmod(0o600)
    if existing != IME:
        android("shell", "ime", "set", IME)
    for _ in range(25):
        info = android("shell", "dumpsys", "input_method")
        # The Android IME may be registered but not bound until a text view gets focus.
        if "mCurId=" + IME + " mHaveConnection=true" in info:
            return
        time.sleep(.2)
    raise RuntimeError("Android keyboard did not bind")

def restore():
    if not SAVED.exists():
        return
    previous = json.loads(SAVED.read_text(encoding="utf-8"))["previous"]
    now = android("shell", "settings", "get", "secure", "default_input_method")
    if previous != IME and now == IME:
        android("shell", "ime", "set", previous)
    SAVED.unlink()
    print("PREVIOUS_KEYBOARD_RESTORED", flush=True)

def sender(messages):
    while not STOP.is_set() or not messages.empty():
        try:
            kind, text, preedit = messages.get(timeout=.2)
        except queue.Empty:
            continue
        try:
            if IME == "com.badung.pickleime/.PickleIME":
                if kind == "delete":
                    data = b"\x02"  # Android am broadcast rejects an empty --es argument.
                    action = "com.badung.pickleime.DELETE"
                elif kind == "key":
                    data = struct.pack(">H", int(text))
                    action = "com.badung.pickleime.KEY"
                elif kind == "state":
                    c, p = text.encode(), preedit.encode()
                    data = struct.pack(">HH", len(c), len(p)) + c + p
                    action = "com.badung.pickleime.STATE"
                else:
                    data = text.encode()
                    action = "com.badung.pickleime.COMMIT"
                package = "com.badung.pickleime"
            else:
                if kind != "commit":
                    raise RuntimeError("Android composing IME not selected")
                data = text.encode()
                action = "ADB_INPUT_B64"
                package = "com.android.adbkeyboard"
            payload = base64.b64encode(data).decode()
            result = android("shell", "am", "broadcast", "-a", action,
                             "-p", package, "--es", "msg", payload)
            if "Broadcast completed: result=0" not in result:
                raise RuntimeError("Android input broadcast failed")
            print("INPUT_OK bytes=" + str(len(data)) + " kind=" + kind, flush=True)
        except Exception as exc:
            print("INPUT_ERROR " + type(exc).__name__, flush=True)
        finally:
            messages.task_done()

def main():
    os.umask(0o077)
    if os.path.lexists(ADDRESS):
        if not Path(ADDRESS).is_socket():
            raise RuntimeError("Existing path is not a socket")
        os.unlink(ADDRESS)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    s.bind(ADDRESS)
    os.chmod(ADDRESS, 0o600)
    s.settimeout(.25)
    messages = queue.Queue(maxsize=256)
    def stop(_sig, _frame):
        STOP.set()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    thread = None
    try:
        ensure_ime()
        thread = threading.Thread(target=sender, args=(messages,), daemon=True)
        thread.start()
        print("RDP_ANDROID_IME_READY", flush=True)
        while not STOP.is_set():
            try:
                payload = s.recv(4096)
            except socket.timeout:
                continue
            message = receive_message(payload)
            if message is None:
                print("INVALID_INPUT", flush=True)
                continue
            try:
                messages.put_nowait(message)
            except queue.Full:
                print("INPUT_QUEUE_FULL", flush=True)
    finally:
        STOP.set()
        if thread:
            thread.join(timeout=10)
        s.close()
        if os.path.lexists(ADDRESS):
            os.unlink(ADDRESS)
        restore()

if __name__ == "__main__":
    if "--self-test" in __import__("sys").argv:
        assert receive_text("안녕 字😀".encode()) == "안녕 字😀"
        assert receive_text(b"") is None
        assert receive_text(b"abc" * 800) is None
        assert receive_message(b"\x01\x00\x00\x00\x03" + "ㅎ".encode()) == ("state", "", "ㅎ")
        assert receive_message(b"\x01\x00\x00\x00\x03" + "하".encode()) == ("state", "", "하")
        assert receive_message(b"\x01\x00\x00\x00\x03" + "한".encode()) == ("state", "", "한")
        assert receive_message(b"\x01\x00\x03\x00\x00" + "한".encode()) == ("state", "한", "")
        assert receive_message(b"\x01\x00\x04\x00\x03" + "한".encode()) is None
        assert receive_message("일반 입력".encode()) == ("commit", "일반 입력", "")
        assert receive_message(b"\x02") == ("delete", "", "")
        assert receive_message(b"\x02bad") is None
        assert receive_message(b"\x03\x0d") == ("key", "66", "")
        assert receive_message(b"\x03\x09") == ("key", "61", "")
        assert receive_message(b"\x03\xff") is None
        assert receive_message(b"\x03\x0d\x00") is None
        print("SELF_TEST_OK")
    else:
        main()
