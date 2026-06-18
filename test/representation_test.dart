import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  // Single point with 2 dims -> shape (1, 2); results collapse to shape (1,).
  MaskedArray pt(double x, double y) => MaskedArray.fromNested([
        [x, y]
      ]);

  group('DistanceRepresentation', () {
    test('euclidean distance', () {
      final r = DistanceRepresentation();
      expect(r(pt(0, 0), pt(3, 4)).toNested(), equals([5]));
    });
  });

  group('AngleRepresentation', () {
    final r = AngleRepresentation();
    test('45 degrees', () {
      expect((r(pt(0, 0), pt(1, 1)).toNested()[0] as num).toDouble(),
          closeTo(pi / 4, 1e-9));
    });
    test('horizontal is zero', () {
      expect((r(pt(0, 0), pt(1, 0)).toNested()[0] as num).toDouble(),
          closeTo(0, 1e-9));
    });
  });

  group('InnerAngleRepresentation', () {
    test('right angle at the corner', () {
      final r = InnerAngleRepresentation();
      // angle at p2=(0,0) between p1=(1,0) and p3=(0,1) is 90 degrees
      final angle =
          (r(pt(1, 0), pt(0, 0), pt(0, 1)).toNested()[0] as num).toDouble();
      expect(angle, closeTo(pi / 2, 1e-6));
    });
  });

  group('PointLineDistanceRepresentation', () {
    test('distance from point to a line', () {
      final r = PointLineDistanceRepresentation();
      // point (0,1); line through (0,0)-(2,0) is the x-axis -> distance 1
      final d =
          (r(pt(0, 1), pt(0, 0), pt(2, 0)).toNested()[0] as num).toDouble();
      expect(d, closeTo(1, 1e-9));
    });
  });

  group('PointsRepresentation', () {
    test('reshapes (P,B,L,D) -> (P*D,B,L) and zero-fills', () {
      // P=2, B=1, L=1, D=2
      final input = MaskedArray.fromNested([
        [
          [
            [1, 2]
          ]
        ],
        [
          [
            [3, 4]
          ]
        ]
      ]);
      final out = PointsRepresentation()(input);
      expect(out.shape, equals([4, 1, 1]));
    });
  });
}
