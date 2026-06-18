import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pose/src/masked_array.dart';
import 'package:pose/src/pose_header.dart';

List<double> _sub(List<double> a, List<double> b) =>
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

List<double> _cross(List<double> a, List<double> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

double _dot(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

double _norm(List<double> a) => math.sqrt(_dot(a, a));

/// 3D pose normalization (port of `pose_format.utils.normalization_3d`).
///
/// Rotates each pose so the [plane] (3 points) normal aligns with Z, rotates in
/// the X-Y plane so the [line] (2 points) lies on the Y axis, then scales the
/// line to [size] and moves its first point to the origin. Requires 3D data.
class PoseNormalizer {
  final PoseNormalizationInfo plane;
  final PoseNormalizationInfo line;
  final double size;

  PoseNormalizer({required this.plane, required this.line, this.size = 1});

  /// Normalizes a batch of poses shaped `(frames, people, joints, 3)`.
  MaskedArray call(MaskedArray poses) {
    if (poses.shape.length != 4 || poses.shape[3] != 3) {
      throw ArgumentError('PoseNormalizer expects shape (frames, people, '
          'joints, 3), got ${poses.shape}');
    }
    final int joints = poses.shape[2];
    final int n = poses.shape[0] * poses.shape[1];

    final Float64List v = Float64List.fromList(poses.values);
    final Uint8List mask = poses.mask;
    for (int p = 0; p < n; p++) {
      _normalizeOne(v, mask, p * joints * 3, joints);
    }
    return MaskedArray(v, Uint8List.fromList(mask), poses.shape.toList());
  }

  void _normalizeOne(Float64List v, Uint8List mask, int base0, int joints) {
    double g(int j, int k) => v[base0 + j * 3 + k];
    void s(int j, int k, double val) => v[base0 + j * 3 + k] = val;
    List<double> point(int j) => [g(j, 0), g(j, 1), g(j, 2)];

    // --- normal of the plane triangle ---
    final List<double> t0 = point(plane.p1);
    final List<double> v1 = _sub(point(plane.p2), t0);
    final List<double> v2 = _sub(point(plane.p3!), t0);
    List<double> normal = _cross(v1, v2);
    final double nMag = _norm(normal);
    normal = [normal[0] / nMag, normal[1] / nMag, normal[2] / nMag];

    // --- rotate so normal aligns with Z (around plane point 0) ---
    final List<double> zAxis = normal;
    final List<double> yAxis = _cross([1, 0, 0], zAxis);
    final List<double> xAxis = _cross(zAxis, yAxis);
    for (int j = 0; j < joints; j++) {
      final List<double> p = _sub(point(j), t0);
      s(j, 0, _dot(p, xAxis));
      s(j, 1, _dot(p, yAxis));
      s(j, 2, _dot(p, zAxis));
    }

    // --- rotate in X-Y so the line lies on the Y axis ---
    final double vx = g(line.p2, 0) - g(line.p1, 0);
    final double vy = g(line.p2, 1) - g(line.p1, 1);
    final double angle = math.pi / 2 + math.atan2(vy, vx);
    final double ca = math.cos(angle), sa = math.sin(angle);
    for (int j = 0; j < joints; j++) {
      final double px = g(j, 0), py = g(j, 1);
      s(j, 0, px * ca + py * sa);
      s(j, 1, -px * sa + py * ca);
    }

    // --- scale the line to `size`, move line.p1 to the origin ---
    final double current = _norm(_sub(point(line.p2), point(line.p1)));
    final double scale = size / current;
    for (int j = 0; j < joints; j++) {
      for (int k = 0; k < 3; k++) {
        s(j, k, g(j, k) * scale);
      }
    }
    final List<double> offset = point(line.p1);
    for (int j = 0; j < joints; j++) {
      for (int k = 0; k < 3; k++) {
        s(j, k, g(j, k) - offset[k]);
      }
    }

    // --- masked points filled with zero ---
    for (int j = 0; j < joints; j++) {
      if (mask[base0 + j * 3] != 0) {
        for (int k = 0; k < 3; k++) {
          s(j, k, 0);
        }
      }
    }
  }
}
