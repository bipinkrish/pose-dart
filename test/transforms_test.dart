import 'dart:io';
import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

/// Builds a minimal single-component pose from nested [data] and [conf].
Pose makeSimplePose(List data, List conf, {double fps = 1}) {
  final int dims = (data[0][0][0] as List).length;
  final int n = (data[0][0] as List).length;
  final String fmt = '${'XYZW'.substring(0, dims)}C';
  final PoseHeaderComponent comp = PoseHeaderComponent(
    'BODY',
    [for (int i = 0; i < n; i++) 'p$i'],
    <Point<int>>[],
    <List<dynamic>>[],
    fmt,
  );
  final PoseHeader header =
      PoseHeader(0.2, PoseHeaderDimensions(100, 100, 100), [comp]);
  return Pose(header, PoseBody(fps, data, conf));
}

Pose readPose(String path) => Pose.read(File(path).readAsBytesSync());

/// Recursively flattens nested lists of numbers to doubles.
Iterable<double> flatten(dynamic x) sync* {
  if (x is List) {
    for (final dynamic e in x) {
      yield* flatten(e);
    }
  } else {
    yield (x as num).toDouble();
  }
}

/// 3 frames, 1 person, 2 points, 2 dims, all confident.
Pose distributionPose() => makeSimplePose([
      [
        [
          [1, 2],
          [3, 4]
        ]
      ],
      [
        [
          [5, 6],
          [7, 8]
        ]
      ],
      [
        [
          [9, 10],
          [11, 12]
        ]
      ],
    ], [
      [
        [1, 1]
      ],
      [
        [1, 1]
      ],
      [
        [1, 1]
      ],
    ]);

void main() {
  group('copy', () {
    test('is a deep copy', () {
      final Pose p = distributionPose();
      final Pose c = p.copy();
      p.body.data[0][0][0][0] = 999;
      expect(c.body.data[0][0][0][0], equals(1));
    });
  });

  group('normalize', () {
    test('auto shoulders -> unit mean shoulder distance', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      pose.normalize();

      final info = poseNormalizationInfo(pose.header);
      final t = pose.body.pointsPerspective();
      final double d = distanceBatch(t.takeFirst(info.p1), t.takeFirst(info.p2))
          .mean()
          .scalar;
      expect(d, closeTo(1.0, 1e-3));
    });

    test('scaleFactor scales the unit distance', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      pose.normalize(scaleFactor: 2.0);

      final info = poseNormalizationInfo(pose.header);
      final t = pose.body.pointsPerspective();
      final double d = distanceBatch(t.takeFirst(info.p1), t.takeFirst(info.p2))
          .mean()
          .scalar;
      expect(d, closeTo(2.0, 1e-3));
    });
  });

  group('normalizeDistribution', () {
    test('produces ~zero mean and ~unit std', () {
      final Pose pose = distributionPose();
      pose.normalizeDistribution();

      final m = pose.body.maskedData;
      for (final double v in flatten(m.mean({0, 1}).toNested())) {
        expect(v, closeTo(0, 1e-9));
      }
      for (final double v in flatten(m.std({0, 1}).toNested())) {
        expect(v, closeTo(1, 1e-9));
      }
    });

    test('unnormalize round-trips', () {
      final Pose pose = distributionPose();
      final Pose original = pose.copy();
      final (mu, std) = pose.normalizeDistribution();
      pose.unnormalizeDistribution(mu, std);

      for (int f = 0; f < 3; f++) {
        for (int n = 0; n < 2; n++) {
          for (int d = 0; d < 2; d++) {
            expect(
                (pose.body.data[f][0][n][d] as num).toDouble(),
                closeTo(
                    (original.body.data[f][0][n][d] as num).toDouble(), 1e-9));
          }
        }
      }
    });
  });

  group('focus', () {
    test('shifts minimum to origin and resizes header', () {
      final Pose pose = distributionPose();
      pose.focus();

      final mins = pose.body.maskedData.min({0, 1, 2}).toNested() as List;
      expect((mins[0] as num).toDouble(), closeTo(0, 1e-9));
      expect((mins[1] as num).toDouble(), closeTo(0, 1e-9));
      // dim0 range 1..11 -> 10, dim1 range 2..12 -> 10
      expect(pose.header.dimensions.width, equals(10));
      expect(pose.header.dimensions.height, equals(10));
    });
  });

  group('matmul / augment2d / flip', () {
    test('matmul identity is a no-op', () {
      final Pose pose = distributionPose();
      final PoseBody r = pose.body.matmul([
        [1, 0],
        [0, 1]
      ]);
      expect(r.data[1][0][1], equals([7, 8]));
    });

    test('matmul scales per dimension', () {
      final Pose pose = distributionPose();
      final PoseBody r = pose.body.matmul([
        [2, 0],
        [0, 3]
      ]);
      expect((r.data[0][0][0][0] as num), equals(2)); // 1*2
      expect((r.data[0][0][0][1] as num), equals(6)); // 2*3
    });

    test('augment2d with zero std is identity', () {
      final Pose pose = distributionPose();
      final PoseBody r = pose.body
          .augment2d(rotationStd: 0, shearStd: 0, scaleStd: 0, rng: Random(1));
      expect(r.data[2][0][1], equals([11, 12]));
    });

    test('augment2d preserves shape', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final PoseBody r = pose.body.augment2d(rng: Random(7));
      expect((r.data as List).length, equals((pose.body.data as List).length));
      expect(r.data[0][0][0].length, equals(3));
    });

    test('flip negates an axis', () {
      final Pose pose = distributionPose();
      final PoseBody r = pose.body.flip(axis: 0);
      expect((r.data[0][0][0][0] as num), equals(-1));
      expect((r.data[0][0][0][1] as num), equals(2)); // y unchanged
    });
  });

  group('components', () {
    test('getComponents keeps only requested component', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final Pose sub = pose.getComponents(['POSE_LANDMARKS']);
      expect(sub.header.components.length, equals(1));
      expect(sub.header.components[0].name, equals('POSE_LANDMARKS'));
      expect(sub.body.data[0][0].length, equals(8));
    });

    test('removeComponents drops a component', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final Pose sub = pose.removeComponents(['FACE_LANDMARKS']);
      final names = [for (final c in sub.header.components) c.name];
      expect(names, isNot(contains('FACE_LANDMARKS')));
      // 8 + 21 + 21 = 50 remaining points
      expect(sub.body.data[0][0].length, equals(50));
    });

    test('getComponents can subset points and remap limbs', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final Pose sub = pose.getComponents([
        'POSE_LANDMARKS'
      ], points: {
        'POSE_LANDMARKS': ['RIGHT_SHOULDER', 'LEFT_SHOULDER']
      });
      expect(sub.header.components[0].points,
          equals(['RIGHT_SHOULDER', 'LEFT_SHOULDER']));
      expect(sub.body.data[0][0].length, equals(2));
    });
  });

  group('frame ops', () {
    test('selectFrames picks frames', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final PoseBody b = pose.body.selectFrames([0, 2, 4]);
      expect((b.data as List).length, equals(3));
      expect((b.confidence).length, equals(3));
    });

    test('sliceStep halves frames and fps', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final int total = (pose.body.data as List).length;
      final PoseBody b = pose.body.sliceStep(2);
      expect((b.data as List).length, equals((total / 2).ceil()));
      expect(b.fps, equals(pose.body.fps / 2));
    });

    test('frameDropoutGivenPercent drops the expected count', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final int total = (pose.body.data as List).length; // 170
      final (b, selected) =
          pose.body.frameDropoutGivenPercent(0.5, rng: Random(3));
      final int expectedDropped =
          min((total * 0.5).toInt(), (total * 0.99).toInt());
      expect(selected.length, equals(total - expectedDropped));
      expect((b.data as List).length, equals(selected.length));
    });
  });

  group('zeroFilled', () {
    test('replaces masked points with zero', () {
      // point1 has zero confidence -> masked -> zeroed
      final Pose pose = makeSimplePose([
        [
          [
            [1, 2],
            [3, 4]
          ]
        ]
      ], [
        [
          [1, 0]
        ]
      ]);
      final PoseBody z = pose.body.zeroFilled();
      expect(z.data[0][0][0], equals([1, 2])); // confident point kept
      expect(z.data[0][0][1], equals([0, 0])); // masked point zeroed
    });
  });

  group('interpolation kernels', () {
    test('linspace endpoints and spacing', () {
      expect(linspace(0, 1, 5), equals([0, 0.25, 0.5, 0.75, 1]));
      expect(linspace(0, 1, 1), equals([0]));
    });

    test('linearInterp', () {
      expect(linearInterp([0, 1], [0, 10], 0.3), closeTo(3, 1e-12));
      expect(linearInterp([0, 2], [0, 10], 1.0), closeTo(5, 1e-12));
    });

    test('cubic spline passes through knots', () {
      final s = NaturalCubicSpline([0, 1, 2], [0, 1, 4]);
      expect(s.eval(0), closeTo(0, 1e-9));
      expect(s.eval(1), closeTo(1, 1e-9));
      expect(s.eval(2), closeTo(4, 1e-9));
    });

    test('cubic spline of collinear data is linear', () {
      final s = NaturalCubicSpline([0, 1, 2], [0, 2, 4]);
      expect(s.eval(0.5), closeTo(1, 1e-9));
      expect(s.eval(1.5), closeTo(3, 1e-9));
    });
  });

  group('interpolate', () {
    Pose twoFramePose() => makeSimplePose([
          [
            [
              [0, 0]
            ]
          ],
          [
            [
              [10, 20]
            ]
          ],
        ], [
          [
            [1]
          ],
          [
            [1]
          ],
        ]);

    test('upsampling doubles the frame count and lerps linearly', () {
      final PoseBody b = twoFramePose().body.interpolate(newFps: 2.0);
      expect((b.data as List).length, equals(4)); // round(2 * 2/1)
      expect((b.data[1][0][0][0] as num).toDouble(), closeTo(10 / 3, 1e-6));
      expect((b.data[1][0][0][1] as num).toDouble(), closeTo(20 / 3, 1e-6));
      expect((b.confidence[1][0][0] as num).toDouble(), closeTo(1, 1e-6));
    });

    test('same fps preserves values', () {
      final PoseBody b = twoFramePose().body.interpolate();
      expect((b.data as List).length, equals(2));
      expect((b.data[0][0][0][0] as num).toDouble(), closeTo(0, 1e-9));
      expect((b.data[1][0][0][0] as num).toDouble(), closeTo(10, 1e-9));
    });

    test('single frame throws', () {
      final Pose p = makeSimplePose([
        [
          [
            [1, 2]
          ]
        ]
      ], [
        [
          [1]
        ]
      ]);
      expect(() => p.body.interpolate(), throwsArgumentError);
    });

    test('points missing in all frames stay zero', () {
      // 2 frames, 2 points; point 1 never confident
      final Pose p = makeSimplePose([
        [
          [
            [1, 1],
            [9, 9]
          ]
        ],
        [
          [
            [3, 3],
            [9, 9]
          ]
        ],
      ], [
        [
          [1, 0]
        ],
        [
          [1, 0]
        ],
      ]);
      final PoseBody b = p.body.interpolate(newFps: 2.0);
      // point 1 stays zero everywhere
      for (final frame in b.data as List) {
        expect((frame[0][1][0] as num), equals(0));
        expect((frame[0][1][1] as num), equals(0));
      }
    });
  });

  group('bbox', () {
    test('reduces a component to min/max points', () {
      final Pose p = makeSimplePose([
        [
          [
            [1, 2],
            [5, 8],
            [3, 4]
          ]
        ]
      ], [
        [
          [1, 1, 1]
        ]
      ]);
      final Pose box = p.bbox();
      expect(box.header.isBbox, isTrue);
      expect(box.header.components[0].points,
          equals(['TOP_LEFT', 'BOTTOM_RIGHT']));
      expect(box.body.data[0][0][0], equals([1, 2])); // min
      expect(box.body.data[0][0][1], equals([5, 8])); // max
    });

    test('on a real pose: two points per component', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final Pose box = pose.bbox();
      expect(
          box.header.components.length, equals(pose.header.components.length));
      expect(box.body.data[0][0].length,
          equals(pose.header.components.length * 2));
    });
  });

  group('small helpers', () {
    test('durationInFrames', () {
      final Pose p = makeSimplePose([
        [
          [
            [0, 0]
          ]
        ],
        [
          [
            [0, 0]
          ]
        ],
        [
          [
            [0, 0]
          ]
        ],
      ], [
        [
          [1]
        ],
        [
          [1]
        ],
        [
          [1]
        ],
      ]);
      expect(p.body.durationInFrames(), equals(3));
      expect(p.body.durationInFrames(startTime: 0, endTime: 2000), equals(3));
    });

    test('slice keeps a frame range', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      final PoseBody b = pose.body.slice(1, 3);
      expect((b.data as List).length, equals(2));
    });

    test('flatten drops zero-confidence points', () {
      final Pose p = makeSimplePose([
        [
          [
            [1, 2],
            [3, 4]
          ]
        ]
      ], [
        [
          [1, 0]
        ]
      ]);
      final rows = p.body.flatten();
      expect(rows.length, equals(1)); // only point 0
      // [time, person, point, conf, x, y]
      expect(rows[0], equals([0, 0, 0, 1, 1, 2]));
    });

    test('toString is informative', () {
      final Pose pose = readPose('test/data/mediapipe.pose');
      expect(pose.toString(), contains('Pose('));
      expect(pose.body.toString(), contains('PoseBody'));
      expect(pose.header.toString(), contains('POSE_LANDMARKS'));
    });
  });
}
