# Pose

[![pub package](https://img.shields.io/pub/v/pose.svg)](https://pub.dev/packages/pose)

This is `dart` implementation of its [python counterpart](https://github.com/sign-language-processing/pose/tree/master/src/python) with limited features

This repository helps developers interested in Sign Language Processing (SLP) by providing a complete toolkit for working with poses.

## File Format Structure

The file format is designed to accommodate any pose type, an arbitrary number of people, and an indefinite number of frames. 
Therefore it is also very suitable for video data, and not only single frames.

At the core of the file format is `Header` and a `Body`.

* The header for example contains the following information:

    - The total number of pose points. (How many points exist.)
    - The exact positions of these points. (Where do they exist.)
    - The connections between these points. (How are they connected.)

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
- ✔️ Visualization (2x slow compared to python and supports only GIF)

See [PORTING.md](PORTING.md) for the full parity roadmap vs. the Python library.

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';

void main() async {
  File file = File("pose_file.pose");
  Uint8List fileContent = file.readAsBytesSync();
  Pose pose = Pose.read(fileContent);
  PoseVisualizer p = PoseVisualizer(pose);
  await p.saveGif("demo.gif", p.draw());
}
```

![Demo Gif](https://raw.githubusercontent.com/bipinkrish/pose/master/test/data/test.gif)
