# Cue Notchpad README Demo

An isolated Remotion project for the Cue Notchpad product demo. It does not
change app source, app settings, the user's Pi profile, or the repository README.
AI rewrite is intentionally not part of the video.

The cut follows the latest authentic macOS screen recording of Ghostty and Cue.
Remotion adds two-line captions, a subtle full-screen zoom, a progress
indicator, and ends on the cover image. It never draws the Cue, Pi, or terminal
interface. The rendered runtime follows the selected footage. Set trim points
after reviewing its actual beginning and end. Without a recording, the edit
displays a clearly marked full-screen slate and renders as an animatic.

## Storyboard

The final chapter boundaries are placed after reviewing the selected recording.
Keep the demonstrated sequence: expand Cue from the Notch, review Pi history,
switch to desktop 2, edit, submit, and return to Pi on desktop 1. Leave Chrome
untouched.

The demo uses a fictional note-taking prompt and a fresh Pi session. Do not
show settings, API credentials, private chats, unrelated windows, or personal
directory listings. Pi's generated example response exists only to make the
external-editor flow genuine; Cue AI rewrite is not shown.

## Prepare the isolated Pi profile

Install project dependencies once, then prepare a temporary Pi agent directory:

```sh
npm install
npm run pi:prepare
```

The script copies the repository's real Pi bridge extension into a new
permission-restricted temporary directory and writes only
`externalEditor: "cue --wait"` to that profile's `settings.json`. It does not
touch `~/.pi`, existing settings, sessions, or credentials. The script prints a
command that launches Pi with the temporary profile. Configure a demo provider
for that profile before the shoot if needed; never record provider settings.
When finished, remove the exact temporary profile path printed by the script.

In Ghostty, run Pi with the isolated profile. Enter a fictional README tagline
request, let Pi answer, scroll through that exchange, then press `Control-G`.
Edit the prompt in Cue and submit with `⌘ Return`. This exercises the actual Pi
extension and `cue --wait` integration.

## Record the real screen

Grant Screen Recording access to the terminal app that runs the script. To list
available macOS capture devices:

```sh
ffmpeg -hide_banner -f avfoundation -list_devices true -i ""
```

Start recording. The script locates the AVFoundation device named `Capture
screen 0` and refuses camera devices. On this Mac, device `0` is the FaceTime
camera and device `1` is the screen:

```sh
npm run record:start
```

Each take gets its own timestamped `screen-demo-*.mp4`; new takes do not
overwrite earlier ones. Rendering selects the newest take.

Run the Pi flow above in Ghostty. The recorder captures the entire display at
1920×1080, with no microphone or system audio. Keep the full screen visible
throughout. Capture the Notch launch, history review, switch to desktop 2, edit,
submit, and return to desktop 1:

```sh
npm run record:stop
```

The resulting local-only file path is printed by `record:start` and saved under
`public/recordings/`. Recording files are git-ignored because the capture may
contain desktop information.
Before rendering, review the recording yourself for notifications or private
content. The screen-capture device index and macOS privacy permission depend on
the machine and cannot be set by this project.

If FFmpeg cannot access a display, use macOS Screenshot/QuickTime Player to
record the same full-screen Ghostty flow and export a 1920×1080 MP4 named
`screen-demo-<timestamp>.mp4` in `public/recordings/`.

## Render and review

After reviewing the newest recording and choosing the useful start and end
times from that footage, render it with trim values in seconds:

```sh
CUE_DEMO_TRIM_START_SECONDS=2.4 CUE_DEMO_TRIM_END_SECONDS=39.8 npm run render
```

Those timestamps are examples only. When omitted, the full selected recording is
used. Review the video for private content and confirm it shows the screen
before rendering.

This writes:

- `out/cue-notchpad-demo.mp4` — 1920×1080 H.264, 30 fps
- `out/cue-notchpad-preview.gif` — 960 px wide animated README preview
- `out/cue-notchpad-cover.png` — 1920×1080 cover still

Open the MP4 and GIF before publishing. The still can be used as the README
poster; GitHub Markdown can display the GIF directly. This project deliberately
does not edit the app's README.

For layout review before screen capture, render the marked animatic:

```sh
ALLOW_STORYBOARD=1 npm run render
```

That output contains the explicit "真实 macOS 录屏待采集" slate and is not a
finished product demo. Do not publish it as the README demo.

## Automation limits

The Pi profile preparation, recording launch/stop, chapter overlays, MP4/GIF
encoding, and cover rendering are automated. macOS must grant the chosen
terminal Screen Recording permission. Pi's `Control-G`, desktop switching,
terminal scrolling, and Cue editing still need actual foreground input.
