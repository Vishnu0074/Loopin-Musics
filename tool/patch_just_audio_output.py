#!/usr/bin/env python3
"""Apply Loopin's Android preferred-output extension to the pinned just_audio plugin.

Run after `flutter pub get`. The patch is intentionally strict and idempotent:
it fails the build if the pinned plugin source changes unexpectedly.
"""
from pathlib import Path
import os
import sys

VERSION = "0.9.46"
CACHE = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
matches = list((CACHE / "hosted" / "pub.dev").glob(f"just_audio-{VERSION}"))
if not matches:
    print(f"just_audio {VERSION} not found in {CACHE}/hosted/pub.dev", file=sys.stderr)
    sys.exit(1)

root = matches[0] / "android" / "src" / "main" / "java" / "com" / "ryanheise" / "just_audio"
audio_player = root / "AudioPlayer.java"
main_handler = root / "MainMethodCallHandler.java"
if not audio_player.is_file() or not main_handler.is_file():
    raise SystemExit("Unsupported just_audio Android source layout; refusing to patch.")

player_text = audio_player.read_text()
player_marker = "    private void setAudioAttributes("
player_method = """    /**
     * Requests a preferred output for this just_audio player only.
     * Android may still override the preference based on device policy.
     */
    public void setPreferredAudioDevice(android.media.AudioDeviceInfo device) {
        if (player != null) {
            player.setPreferredAudioDevice(device);
        }
    }

"""
if "public void setPreferredAudioDevice(android.media.AudioDeviceInfo device)" not in player_text:
    if player_marker not in player_text:
        raise SystemExit("Could not locate AudioPlayer.setAudioAttributes insertion point.")
    player_text = player_text.replace(player_marker, player_method + player_marker, 1)
    audio_player.write_text(player_text)

handler_text = main_handler.read_text()
case_marker = """        default:
            result.notImplemented();
            break;
"""
handler_case = """        case "setPreferredAudioDevice": {
            if (android.os.Build.VERSION.SDK_INT < 23) {
                result.error("UNSUPPORTED", "Per-player output routing requires Android 6.0 or later.", null);
                break;
            }
            Integer deviceId = call.argument("deviceId");
            android.media.AudioDeviceInfo preferredDevice = null;
            if (deviceId != null) {
                android.media.AudioManager audioManager =
                    (android.media.AudioManager)applicationContext.getSystemService(Context.AUDIO_SERVICE);
                for (android.media.AudioDeviceInfo device :
                        audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)) {
                    if (device.getId() == deviceId) {
                        preferredDevice = device;
                        break;
                    }
                }
                if (preferredDevice == null) {
                    result.error("DEVICE_UNAVAILABLE", "The selected audio output is no longer connected.", null);
                    break;
                }
            }
            for (AudioPlayer player : players.values()) {
                player.setPreferredAudioDevice(preferredDevice);
            }
            result.success(players.size());
            break;
        }
"""
if '"setPreferredAudioDevice"' not in handler_text:
    if case_marker not in handler_text:
        raise SystemExit("Could not locate MainMethodCallHandler switch insertion point.")
    handler_text = handler_text.replace(case_marker, handler_case + case_marker, 1)
    main_handler.write_text(handler_text)

print(f"Patched just_audio {VERSION} for per-player preferred output routing.")
