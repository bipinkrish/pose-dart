import 'dart:io';
import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

double dist(List a, List b) {
  double s = 0;
  for (int i = 0; i < a.length; i++) {
    final d = (a[i] as num).toDouble() - (b[i] as num).toDouble();
    s += d * d;
  }
  return sqrt(s);
}

void main() {
  test('PoseNormalizer places the line on the Y axis at unit length', () {
    // 1 frame, 1 person, 4 joints, 3 dims (all in the z=0 plane)
    final poses = MaskedArray.fromNested([
      [
        [
          [0, 0, 0], // p0  (plane & line start)
          [1, 0, 0], // p1  (plane)
          [0, 1, 0], // p2  (plane)
          [2, 0, 0], // p3  (line end)
        ]
      ]
    ]);
    final normalizer = PoseNormalizer(
      plane: PoseNormalizationInfo(0, 1, 2),
      line: PoseNormalizationInfo(0, 3),
    );
    final out = normalizer(poses).toNested();
    final p0 = out[0][0][0] as List;
    final p3 = out[0][0][3] as List;

    expect(dist(p0, [0, 0, 0]), closeTo(0, 1e-9)); // line start at origin
    expect(dist(p0, p3), closeTo(1, 1e-9)); // line scaled to size 1
    expect((p3[0] as num).toDouble(), closeTo(0, 1e-9)); // on the Y axis
    expect((p3[2] as num).toDouble(), closeTo(0, 1e-9)); // in the X-Y plane
  });

  test('normalizeHands3d appends normalized hand points to the body', () {
    final pose = Pose.read(File('test/data/mediapipe.pose').readAsBytesSync());
    final int before = (pose.body.data[0][0] as List).length; // 178
    normalizeHands3d(pose);
    final int after = (pose.body.data[0][0] as List).length;
    expect(after, equals(before + 21 + 21)); // two hands appended
    expect((pose.body.confidence[0][0] as List).length, equals(after));
  });
}
