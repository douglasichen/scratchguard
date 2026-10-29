# ScratchGuard ✋

I have scalp eczema, and I wanted something that would interrupt me when I reach up to scratch my head. ScratchGuard watches my camera locally and plays a random meme sound as soon as it detects a hand near my head—including **FAHHHH**. The idea is to catch the habit quickly while I am using my Mac.

This is a personal habit reminder, not a treatment for eczema. It detects head touching, not a medical condition or scratching specifically.

## What it does

- Lives in the macOS menu bar; closing the settings window keeps monitoring running.
- Starts quietly in the menu bar after camera permission has been granted.
- Detects a hand near your head on the first qualifying frame, without waiting for scratching motion.
- Plays one of **10 meme sounds** randomly, avoiding consecutive repeats.
- Repeats alerts at most once every four seconds.
- Offers sensitivity adjustment, camera preview, a test button, pause, and launch at login.
- Processes camera frames locally with Apple Vision. No recordings or uploads.

## Build and run

Requires an Apple silicon Mac, macOS 13 or later, and Apple command-line developer tools.

```sh
./build.sh
open build/ScratchGuard.app
```

Click **Start monitoring** and allow camera access. Use the hand icon in the top-right menu bar to open settings, start/pause, or quit. Enable **Launch at login** if desired. A previously active session resumes on launch when camera permission remains authorized. Keep the app in a stable location; after moving it, toggle launch at login off and on.

Monitoring requires an awake Mac and a working camera. Camera access remains revocable. Updates to this locally signed app may prompt for camera permission again.

## Detection limits

Normal head touching also triggers alerts. Poor lighting, hidden hands, and an obscured face can cause misses. The sensitivity slider adjusts the region around the head. Frames are checked up to roughly 16 times per second, subject to actual camera and Vision processing speed. This is a simple proximity heuristic; accuracy and latency are not formally benchmarked.

## Sounds

The collection includes FAHHHH, Vine Boom, Anime Wow, Among Us role reveal, dramatic brass, error, Aayein, ACK, notification, and slap clips. Audio is bundled for offline playback at 65% player volume, relative to your system volume.

See [SOUND_SOURCES.md](SOUND_SOURCES.md) for download URLs. Third-party audio belongs to its respective rights holders; this repository does not claim ownership or grant a license to those clips.

## Detector checks

```sh
xcrun swiftc Detector.swift tests/main.swift -o /tmp/scratchguard-check
/tmp/scratchguard-check
```

Checks cover immediate alerts, absent hands, cooldown, repeat reminders, and restart behavior.
