import 'dart:io';
import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  Pose readPose() =>
      Pose.read(File('test/data/mediapipe.pose').readAsBytesSync());

  test('getComponentNames', () {
    final names = getComponentNames(readPose().header);
    expect(
        names,
        equals([
          'POSE_LANDMARKS',
          'FACE_LANDMARKS',
          'LEFT_HAND_LANDMARKS',
          'RIGHT_HAND_LANDMARKS'
        ]));
  });

  test('detectKnownPoseFormat -> holistic', () {
    expect(detectKnownPoseFormat(readPose().header),
        equals(KnownPoseFormat.holistic));
  });

  group('poseHideLegs', () {
    test('hide zeroes hip points', () {
      final Pose pose = readPose();
      final int hip = pose.header.getPointIndex('POSE_LANDMARKS', 'LEFT_HIP');
      poseHideLegs(pose);
      // every frame: hip confidence and data zeroed
      for (int f = 0; f < (pose.body.data as List).length; f++) {
        expect((pose.body.confidence[f][0][hip] as num), equals(0));
        expect(pose.body.data[f][0][hip], everyElement(equals(0)));
      }
    });

    test('remove drops hip points from the header', () {
      final Pose pose = readPose();
      final Pose hidden = poseHideLegs(pose, remove: true);
      final body = hidden.header.components
          .firstWhere((c) => c.name == 'POSE_LANDMARKS');
      expect(body.points, isNot(contains('LEFT_HIP')));
      expect(body.points, isNot(contains('RIGHT_HIP')));
      expect(body.points.length, equals(6)); // 8 - 2 hips
    });
  });

  test('correctWrists copies hand wrist into the body wrist', () {
    final Pose pose = readPose();
    final int handWrist =
        pose.header.getPointIndex('LEFT_HAND_LANDMARKS', 'WRIST');
    final int bodyWrist =
        pose.header.getPointIndex('POSE_LANDMARKS', 'LEFT_WRIST');

    // find a frame where the hand wrist is confident
    int frame = -1;
    final data = pose.body.data as List;
    for (int f = 0; f < data.length; f++) {
      if ((pose.body.confidence[f][0][handWrist] as num) > 0) {
        frame = f;
        break;
      }
    }
    expect(frame, greaterThanOrEqualTo(0),
        reason: 'need a confident hand wrist');

    final List expected = List.from(data[frame][0][handWrist] as List);
    final Pose corrected = correctWrists(pose);
    for (int d = 0; d < expected.length; d++) {
      expect((corrected.body.data[frame][0][bodyWrist][d] as num).toDouble(),
          closeTo((expected[d] as num).toDouble(), 1e-9));
    }
  });

  test('normalizePoseSize sets header dimensions', () {
    final Pose pose = normalizePoseSize(readPose(), targetWidth: 256);
    expect(pose.header.dimensions.width, equals(256));
    expect(pose.header.dimensions.height, equals(256));
  });

  test('reduceHolistic keeps the expected components', () {
    final Pose reduced = reduceHolistic(readPose());
    final names = getComponentNames(reduced.header);
    expect(names, isNot(contains('POSE_WORLD_LANDMARKS')));
    expect(names, contains('POSE_LANDMARKS'));
    expect(names, contains('FACE_LANDMARKS'));
    // body keeps shoulders/elbows/wrists/hips (no face/hand/foot substrings)
    final body =
        reduced.header.components.firstWhere((c) => c.name == 'POSE_LANDMARKS');
    expect(body.points.length, equals(8));
  });

  test('fakePose builds a pose with the requested shape', () {
    final comp = PoseHeaderComponent(
      'BODY',
      ['a', 'b', 'c'],
      <Point<int>>[],
      <List<dynamic>>[],
      'XYZC',
    );
    final Pose fake =
        fakePose(5, numPeople: 2, components: [comp], rng: Random(0));
    expect((fake.body.data as List).length, equals(5));
    expect(fake.body.data[0].length, equals(2));
    expect(fake.body.data[0][0].length, equals(3)); // points
    expect(fake.body.data[0][0][0].length, equals(3)); // dims (XYZ)
    expect(fake.header.numDims(), equals(3));
  });
}
