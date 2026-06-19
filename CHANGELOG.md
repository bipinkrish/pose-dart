## 1.0.0

- Can Load Pose File

## 1.0.1

- Add Documentation

## 1.0.2

- Add More Tests

## 1.1.0

- Add Visualization

## 1.1.1

- Fix Visualization

## 1.1.2

- Removed Unused files
- Re-structre

## 1.1.3

- Optimizations

## 1.1.4

- Method Divide

## 1.1.5

- Async Tasks

## 1.1.6

- Support v0.2 files

## 1.1.7

- Support background color

## 1.2.0

- Add `.pose` file writing (`Pose.write()`, `BufferWriter`, v0.2 output)
- Add `MaskedArray` and interpolation (linear + cubic spline)
- Add geometry representations, optical flow, and transform utilities
- Add 3D normalization (`PoseNormalizer`, `normalizeHands3d`) and pose format conversion
- Add OpenPose and AlphaPose loading
- Add standard pose format tables and fake pose generators
- Add `pose_info` CLI
- Enhance visualization and performance

## 1.2.1

- Expand README with a full Dart usage guide (installation, read/write, normalization, augmentation, interpolation, visualization, OpenPose/AlphaPose loading, fake data, CLI, and tests)
- Update package description to reflect the complete API surface
- Minor refactors: add library declaration in `interpolate.dart`, tidy `PoseVisualizer` constructor usage
