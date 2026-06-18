import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  // src shape (frames, people, points, dims)
  MaskedArray src() => MaskedArray.fromNested([
        [
          [
            [0, 0]
          ]
        ],
        [
          [
            [3, 4]
          ]
        ],
        [
          [
            [3, 4]
          ]
        ],
      ]);

  test('flow magnitude normalized by fps', () {
    final out = OpticalFlowCalculator(1.0)(src());
    // (frames-1, people, points) = (2, 1, 1)
    expect(out.shape, equals([2, 1, 1]));
    expect((out.toNested()[0][0][0] as num).toDouble(), closeTo(5, 1e-9));
    expect((out.toNested()[1][0][0] as num).toDouble(), closeTo(0, 1e-9));
  });

  test('fps scales the flow', () {
    final out = OpticalFlowCalculator(2.0)(src());
    expect((out.toNested()[0][0][0] as num).toDouble(), closeTo(10, 1e-9));
  });
}
