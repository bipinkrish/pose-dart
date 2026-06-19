# Pose

[![pub package](https://img.shields.io/pub/v/pose.svg)](https://pub.dev/packages/pose)

Dart implementation of the [pose-format](https://github.com/sign-language-processing/pose) library for Sign Language Processing (SLP). This package reads, writes, normalizes, augments, interpolates, transforms, and visualizes `.pose` files in pure Dart.

> Native features (MediaPipe pose estimation, mp4 video I/O) are out of scope for
> this package — see [doc/phase4-native.md](doc/phase4-native.md) for the design
> of an optional `pose_flutter` add-on.

### File Format Structure

The `.pose` format accommodates any pose type, an arbitrary number of people, and an indefinite number of frames. At the core are a `Header` and a `Body`

Binary layout details are in the [pose-format specification](https://github.com/sign-language-processing/pose/blob/master/docs/specs/v0.1.md).

## Features

- ✔️ Reading (v0.0, v0.1, v0.2; optional frame/time slicing)
- ✔️ Writing (`Pose.write()` → v0.2 bytes)
- ✔️ Normalizing (`normalize`, `normalizeDistribution`, `focus`)
- ✔️ Augmentation (`augment2d`, `flip`, `matmul`)
- ✔️ Interpolation (`interpolate`; linear + cubic spline)
- ✔️ Transforms (`getComponents`/`removeComponents`, `getPoints`, `selectFrames`, `sliceStep`, `bbox`, frame dropout)
- ✔️ Geometry representations (`distance`, `angle`, `innerAngle`, `pointLineDistance`) + `OpticalFlowCalculator`
- ✔️ Holistic utils (`poseHideLegs`, `correctWrists`, `reduceHolistic`, `normalizePoseSize`)
- ✔️ 3D normalization (`PoseNormalizer`, `normalizeHands3d`) + format conversion (`convertPose`)
- ✔️ OpenPose & AlphaPose loading (`loadOpenpose`, `loadOpenposeDirectory`, `loadAlphapose`)
- ✔️ Standard format tables + fakes (`holisticComponents`, `openposeComponents`, `fakeHolisticPose`, …)
- ✔️ Visualization → GIF and PNG/APNG (`saveGif`, `savePng`)
- ✔️ `pose_info` CLI (`dart run pose:pose_info <file.pose>`)

## Dart Usage Guide

### 1. Installation

```bash
dart pub add pose
```

Or add to `pubspec.yaml`:

```yaml
dependencies:
  pose: ^1.2.1
```

### 2. Reading and Writing `.pose` Files

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';

// Read a .pose file
final Uint8List bytes = File('file.pose').readAsBytesSync();
final Pose pose = Pose.read(bytes);

// Optional frame/time slicing (mutually exclusive per side)
final Pose slice = Pose.read(bytes, startFrame: 10, endFrame: 50);
final Pose timeSlice = Pose.read(bytes, startTime: 0, endTime: 5000);

// Access data
final dynamic data = pose.body.data;           // [frames][people][points][dims]
final dynamic confidence = pose.body.confidence;

// Write back to v0.2 bytes
final Uint8List out = pose.write();
File('output.pose').writeAsBytesSync(out);
```

### 3. Data Manipulation

#### Normalizing Data

```dart
// Scale so shoulder width is consistent (auto-detects format)
pose.normalize();

// Or specify the two reference points manually
pose.normalize(
  info: pose.header.normalizationInfo(
    p1: ('pose_keypoints_2d', 'RShoulder'),
    p2: ('pose_keypoints_2d', 'LShoulder'),
  ),
);

// Zero-mean, unit-variance per keypoint/dimension
final (mu, std) = pose.normalizeDistribution(axis: {0, 1, 2});
pose.unnormalizeDistribution(mu, std);

// Shift to origin and resize header dimensions to fit
pose.focus();
```

#### Augmentation

```dart
// Random 2D rotation, shear, and scaling
pose.body.augment2d(rotationStd: 0.2, shearStd: 0.2, scaleStd: 0.2);

// Horizontal flip
pose.body.flip(axis: 0);
```

#### Interpolation

```dart
// Resample to a new frame rate (linear or cubic spline)
pose.body.interpolate(newFps: 24, kind: 'cubic');
pose.body.interpolate(newFps: 24, kind: 'linear');
```

#### Transforms

```dart
// Keep only selected components
final Pose subset = pose.getComponents(
  ['POSE_LANDMARKS', 'LEFT_HAND_LANDMARKS'],
  points: {'POSE_LANDMARKS': ['LEFT_SHOULDER', 'RIGHT_SHOULDER']},
);

// Remove components or individual points
final Pose trimmed = pose.removeComponents(
  ['FACE_LANDMARKS'],
  pointsToRemove: {'POSE_LANDMARKS': ['LEFT_ANKLE', 'RIGHT_ANKLE']},
);

// Bounding box, frame selection, dropout
final Pose boxed = pose.bbox();
final PoseBody frames = pose.body.selectFrames([0, 5, 10]);
final (Pose dropped, List<int> kept) = pose.frameDropoutUniform();
```

#### Geometry Representations

```dart
import 'package:pose/pose.dart';

final MaskedArray points = pose.body.pointsPerspective();
final distance = DistanceRepresentation()(p1s, p2s);
final angle = AngleRepresentation()(p1s, p2s);
final innerAngle = InnerAngleRepresentation()(p1s, p2s, p3s);

final flow = OpticalFlowCalculator(pose.body.fps)(points);
```

#### Holistic Utilities & 3D Normalization

```dart
poseHideLegs(pose);          // zero out leg keypoints
correctWrists(pose);         // align hand wrists with body wrists
final Pose reduced = reduceHolistic(pose);
normalizePoseSize(pose, targetWidth: 512);

normalizeHands3d(pose);      // append 3D-normalized hand points

// Convert between OpenPose and Holistic layouts
final Pose converted = convertPose(pose, holisticComponents());
```

### 4. Visualization

```dart
import 'package:pose/pose.dart';

final Pose pose = Pose.read(File('example.pose').readAsBytesSync());
final visualizer = PoseVisualizer(pose);

// Save as GIF
await visualizer.saveGif('example.gif', visualizer.draw());

// Custom background color (RGBA)
await visualizer.saveGif(
  'example.gif',
  visualizer.draw(backgroundColor: [255, 255, 255, 255]),
);

// Save as animated PNG
await visualizer.savePng('example.png', visualizer.draw());

// Normalize before drawing (optional)
pose.normalize();
await visualizer.saveGif('normalized.gif', visualizer.draw());
```

![Demo Gif](https://raw.githubusercontent.com/bipinkrish/pose-dart/refs/heads/main/test/data/test.gif)

### 5. Integration with External Data Sources

#### Loading OpenPose Data

```dart
import 'package:pose/pose.dart';

// From a directory of *_keypoints.json files (137-keypoint model)
final Pose openpose = loadOpenposeDirectory(
  '/path/to/openpose/directory',
  fps: 24,
  width: 1000,
  height: 1000,
);

// OpenPose-135 variant — pass openpose135Components()
final Pose op135 = loadOpenposeDirectory(
  '/path/to/openpose_135/directory',
  components: openpose135Components(),
);
```

#### Loading AlphaPose WholeBody JSON

```dart
// 133-keypoint variant (default)
final Pose alpha = loadAlphapose(framesKeypoints);

// Custom component layout — pass your own PoseHeaderComponent list
final Pose custom = loadAlphapose(
  framesKeypoints,
  components: myComponents,
);
```

### 6. Generating Fake Pose Data for Testing

```dart
import 'package:pose/pose.dart';

final Pose fake = fakeHolisticPose(numFrames: 10, numPeople: 1, fps: 25.0);
final Pose fakeOp = fakeOpenposePose(numFrames: 10);
final Pose fakeOp135 = fakeOpenpose135Pose(numFrames: 10);
```

### 7. CLI

Inspect a `.pose` file from the command line:

```bash
dart run pose:pose_info example.pose
```

### 8. Running Tests

```bash
dart test
```

## Acknowledging the Work

If you use this toolkit in your research or projects, please consider citing the original [pose-format](https://github.com/sign-language-processing/pose) work:

```bibtex
@misc{moryossef2021pose-format,
    title={pose-format: Library for viewing, augmenting, and handling .pose files},
    author={Moryossef, Amit and M\"{u}ller, Mathias and Fahrni, Rebecka},
    howpublished={\url{https://github.com/sign-language-processing/pose}},
    year={2021}
}
```
