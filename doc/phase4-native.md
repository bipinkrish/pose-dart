# Phase 4 — Native features (Flutter add-on)

This document is a **design guide for future work**. Nothing here is implemented
in the `pose` package; it describes how to add the features that cannot be done
in pure Dart, as a *separate* package layered on top of this one.

## Why a separate package

The `pose` package is **pure Dart** — its only dependencies (`image`, `tuple`)
run anywhere Dart runs: CLI, server, web, and inside Flutter apps. The Phase 4
features below require the **Flutter SDK and/or native platform code**
(MediaPipe, camera, ffmpeg). Adding those here would force every consumer to
depend on Flutter and break pure-Dart usage.

So the native work belongs in a **new package** — call it `pose_flutter` — that
declares `dependency: pose` and adds the Flutter/native pieces. This mirrors the
standard ecosystem split (e.g. `http` core + platform adapters).

```
repo/
  packages/
    pose/          # this package — pure Dart core (unchanged)
    pose_flutter/  # NEW — Flutter plugin; depends on pose
```

Either restructure this repo into a monorepo (melos/workspaces) or create
`pose_flutter` as its own repo that depends on `pose` from pub.

## What's blocked in pure Dart (the Phase 4 scope)

| Feature | Python reference | Why it needs native |
|---|---|---|
| Pose **estimation** (video/image → `.pose`) | `utils/holistic.py`, `bin/pose_estimation.py`, `bin/directory.py` | MediaPipe Holistic is a native C++/ML runtime; no pure-Dart port |
| Video **input** (`draw_on_video`, background video) | `pose_visualizer.py:draw_on_video` | Needs a video decoder (ffmpeg/OpenCV) |
| Video **output** (`save_video`, mp4) | `pose_visualizer.py:save_video` | Needs a video encoder (ffmpeg) |

> GIF and PNG/APNG output are **already done** in the core (`saveGif`,
> `savePng`) — only true video codecs are out of scope here.

---

## Feature 1 — Pose estimation (the big one)

**Goal:** mirror Python's `pose_video(input, output, format)` — run an estimator
over a video/camera and produce a core `Pose`.

**Estimator options (Flutter):**
- `google_mlkit_pose_detection` — easy, on-device, but **only 33 body
  landmarks** (no hands/face). Good enough for body-only use cases.
- A MediaPipe Tasks plugin / FFI binding to `mediapipe` C++ — gives **Holistic**
  (body + 2 hands + face = the 543/576-point layout). More work; may need a
  custom plugin per platform.
- Server-side: call a Python `pose_format` service over HTTP and `Pose.read` the
  bytes — no native code at all, but needs a backend.

**Integration point (already in the core):** the component tables are ported, so
the estimator just maps detected landmarks into them:

```dart
import 'package:pose/pose.dart';

Pose buildHolisticPose(List<FrameLandmarks> frames, double fps, int w, int h) {
  final header = PoseHeader(
      0.2, PoseHeaderDimensions(w, h, 0), holisticComponents()); // ← core table
  // data: [frames][people=1][points=576][dims=3], confidence: [...][576]
  final data = <dynamic>[];
  final confidence = <dynamic>[];
  for (final f in frames) {
    // map MediaPipe pose/face/hand landmarks into the 576-point order
    data.add([landmarksToPoints(f)]);
    confidence.add([landmarksToConfidence(f)]);
  }
  return Pose(header, PoseBody(fps, data, confidence));
}
```

Then `pose.write()` (core) serializes it to a `.pose` file — so `pose_flutter`
only has to produce the landmark arrays; serialization, transforms, and
visualization are all reused from the core.

**`videos_to_poses` (directory):** port `bin/directory.py` — find videos lacking
a sibling `.pose`, estimate, and write. Pure orchestration on top of the
estimator; can live in `pose_flutter`'s `bin/` or as a desktop CLI.

---

## Feature 2 — Video output (`save_video`)

**Goal:** mirror `PoseVisualizer.save_video` — render the pose to an `.mp4`.

The core already produces a `Stream<Image>` of rendered frames
(`PoseVisualizer.draw()`). Phase 4 only needs to encode those frames to video:

- **Desktop/server (can even be pure Dart!):** shell out to the `ffmpeg` binary
  via `dart:io` `Process` — pipe raw frames to stdin. This needs **no Flutter**,
  so a `save_video` helper for desktop could optionally live in a small
  `pose_ffmpeg` package rather than `pose_flutter`.
- **Mobile (Flutter):** `ffmpeg_kit_flutter` to encode frames written to a temp
  dir.

```dart
// Desktop sketch (pure Dart, ffmpeg on PATH):
Future<void> saveVideo(PoseVisualizer v, String out, {double fps = 24}) async {
  final p = await Process.start('ffmpeg', [
    '-y', '-f', 'image2pipe', '-framerate', '$fps', '-i', '-',
    '-pix_fmt', 'yuv420p', out,
  ]);
  await for (final frame in v.draw()) {
    p.stdin.add(encodePng(frame));
  }
  await p.stdin.close();
  await p.exitCode;
}
```

## Feature 3 — Video input (`draw_on_video`)

**Goal:** mirror `draw_on_video` — overlay the pose on the original video frames.

- Decode the background video to frames (ffmpeg `image2pipe` out, or a camera/
  video plugin).
- Pass each decoded frame as the background into a per-frame draw (the core
  `_drawFrame` is private; expose a `drawOnFrames(Stream<Image> background)`
  hook in the core if needed, or render in `pose_flutter`).
- Re-encode (Feature 2).

A small core change would help: make `PoseVisualizer.draw` accept an optional
`Stream<Image>` of background frames. That's a pure-Dart addition that keeps the
codec work in the add-on.

---

## Platform matrix

| Target | Estimation | Video in/out |
|---|---|---|
| Desktop (macOS/Win/Linux) | MediaPipe FFI, or HTTP service | `ffmpeg` binary (pure Dart `Process`) |
| Mobile (Flutter) | ML Kit (body) / MediaPipe plugin | `ffmpeg_kit_flutter` |
| Web | MediaPipe Tasks (JS interop) | MediaRecorder / WebCodecs |
| Server (pure Dart) | HTTP to a Python service | `ffmpeg` binary |

## Core changes that would help (small, pure-Dart, do in `pose`)

These keep the heavy stuff in the add-on while making it pluggable:
1. Optional `background` frame stream on `PoseVisualizer.draw` (for `draw_on_video`).
2. A public `drawFrame(frameData, confidence, Image background)` method (currently `_drawFrame` is private).
3. An `PoseEstimator` interface (`Pose estimate(...)`) the add-on implements — so apps depend only on the core abstraction.

## Testing strategy

- Estimation: golden-file test — run the estimator on a fixed short clip, assert
  the produced `.pose` matches a checked-in fixture (within tolerance).
- Video out: assert the output file exists, is non-empty, and `ffprobe` reports
  the expected frame count/fps.
- Keep these tests in `pose_flutter` (they need the native toolchain); the core
  stays fast and pure.

## Python references

- `src/python/pose_format/utils/holistic.py` — MediaPipe Holistic → `Pose`
- `src/python/pose_format/bin/pose_estimation.py` — `video_to_pose` CLI
- `src/python/pose_format/bin/directory.py` — `videos_to_poses` batch CLI
- `src/python/pose_format/pose_visualizer.py` — `draw_on_video`, `save_video`
