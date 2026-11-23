package com.badung.pickleime;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.inputmethodservice.InputMethodService;
import android.util.Base64;
import android.util.Log;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

public final class PickleIME extends InputMethodService {
    private static final String TAG = "PickleIME";
    private static final String ACTION_COMMIT = "com.badung.pickleime.COMMIT";
    private static final String ACTION_STATE = "com.badung.pickleime.STATE";
    private static final String ACTION_DELETE = "com.badung.pickleime.DELETE";
    private static final String ACTION_KEY = "com.badung.pickleime.KEY";
    private static final int MAX_BYTES = 2048;
    private boolean composing;

    private final BroadcastReceiver relay = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            InputConnection ic = getCurrentInputConnection();
            if (ic == null) return;

            String encoded = intent.getStringExtra("msg");
            if (encoded == null || encoded.length() > MAX_BYTES * 2) return;
            byte[] data;
            try {
                data = Base64.decode(encoded, Base64.DEFAULT);
            } catch (IllegalArgumentException ex) {
                return;
            }
            if (data.length > MAX_BYTES) return;

            if (ACTION_DELETE.equals(intent.getAction())) {
                ic.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL));
                ic.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL));
                return;
            }
            if (ACTION_KEY.equals(intent.getAction())) {
                if (data.length != 2) return;
                int code = ByteBuffer.wrap(data).getShort() & 0xffff;
                switch (code) {
                    case KeyEvent.KEYCODE_ENTER:
                    case KeyEvent.KEYCODE_TAB:
                    case KeyEvent.KEYCODE_DPAD_LEFT:
                    case KeyEvent.KEYCODE_DPAD_RIGHT:
                    case KeyEvent.KEYCODE_DPAD_UP:
                    case KeyEvent.KEYCODE_DPAD_DOWN:
                    case KeyEvent.KEYCODE_MOVE_HOME:
                    case KeyEvent.KEYCODE_MOVE_END:
                    case KeyEvent.KEYCODE_FORWARD_DEL:
                    case KeyEvent.KEYCODE_PAGE_UP:
                    case KeyEvent.KEYCODE_PAGE_DOWN:
                    case KeyEvent.KEYCODE_ESCAPE:
                        ic.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, code));
                        ic.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, code));
                        return;
                    default: return;
                }
            }
            if (ACTION_COMMIT.equals(intent.getAction())) {
                String text = new String(data, StandardCharsets.UTF_8);
                if (!text.isEmpty()) {
                    ic.commitText(text, 1);
                    composing = false;
                }
                return;
            }
            if (!ACTION_STATE.equals(intent.getAction()) || data.length < 4) return;
            ByteBuffer buf = ByteBuffer.wrap(data);
            int committedLen = buf.getShort() & 0xffff;
            int preeditLen = buf.getShort() & 0xffff;
            if (committedLen + preeditLen != buf.remaining()) return;

            byte[] part = new byte[committedLen];
            buf.get(part);
            String committed = new String(part, StandardCharsets.UTF_8);
            part = new byte[preeditLen];
            buf.get(part);
            String preedit = new String(part, StandardCharsets.UTF_8);
            ic.beginBatchEdit();
            try {
                if (!committed.isEmpty()) {
                    // commitText replaces the previous in-progress syllable.
                    ic.commitText(committed, 1);
                    composing = false;
                }
                if (!preedit.isEmpty()) {
                    ic.setComposingText(preedit, 1);
                    composing = true;
                } else if (composing) {
                    // Backspace can remove the entire in-progress syllable.
                    ic.setComposingText("", 1);
                    ic.finishComposingText();
                    composing = false;
                }
            } finally {
                ic.endBatchEdit();
            }
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_COMMIT);
        filter.addAction(ACTION_STATE);
        filter.addAction(ACTION_DELETE);
        filter.addAction(ACTION_KEY);
        // Only the ADB shell (which has DUMP permission) may send text.
        registerReceiver(relay, filter, android.Manifest.permission.DUMP, null);
        Log.i(TAG, "RDP input receiver ready");
    }

    @Override public void onDestroy() {
        unregisterReceiver(relay);
        super.onDestroy();
    }

    @Override public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        composing = false;
    }

    @Override public void onFinishInput() {
        composing = false;
        super.onFinishInput();
    }

    @Override public boolean onEvaluateInputViewShown() {
        return false;
    }
}
