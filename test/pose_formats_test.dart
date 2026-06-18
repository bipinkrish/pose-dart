import 'package:pose/pose.dart';
import 'package:test/test.dart';

int totalPoints(List<PoseHeaderComponent> components) =>
    components.fold(0, (a, c) => a + c.points.length);

void main() {
  group('component tables have the expected point counts', () {
    test('openpose = 137', () {
      final c = openposeComponents();
      expect(
          c.map((x) => x.name).toList(),
          equals([
            'pose_keypoints_2d',
            'face_keypoints_2d',
            'hand_left_keypoints_2d',
            'hand_right_keypoints_2d'
          ]));
      expect(totalPoints(c), equals(25 + 70 + 21 + 21));
    });

    test('openpose_135 = 135', () {
      expect(totalPoints(openpose135Components()), equals(135));
    });

    test('holistic = 576 (33 + 468 + 21 + 21 + 33)', () {
      final c = holisticComponents();
      expect(c.length, equals(5));
      expect(c[0].points.length, equals(33)); // POSE_LANDMARKS
      expect(c[1].points.length, equals(468)); // FACE_LANDMARKS
      expect(totalPoints(c), equals(33 + 468 + 21 + 21 + 33));
    });

    test('alphapose_133 = 133', () {
      expect(totalPoints(alphapose133Components()), equals(23 + 68 + 21 + 21));
    });
  });

  test('getStandardComponentsForKnownFormat', () {
    expect(getStandardComponentsForKnownFormat(KnownPoseFormat.holistic).length,
        equals(5));
    expect(getStandardComponentsForKnownFormat(KnownPoseFormat.openpose).length,
        equals(4));
  });

  group('fake pose generators', () {
    test('fakeHolisticPose has 576 points and is detected as holistic', () {
      final Pose pose = fakeHolisticPose(2);
      expect((pose.body.data as List).length, equals(2));
      expect(pose.body.data[0][0].length, equals(576));
      expect(pose.body.data[0][0][0].length, equals(3)); // XYZ
      expect(
          detectKnownPoseFormat(pose.header), equals(KnownPoseFormat.holistic));
    });

    test('fakeOpenposePose has 137 points (XY)', () {
      final Pose pose = fakeOpenposePose(3);
      expect(pose.body.data[0][0].length, equals(137));
      expect(pose.body.data[0][0][0].length, equals(2));
    });

    test('fakeOpenpose135Pose has 135 points', () {
      expect(fakeOpenpose135Pose(1).body.data[0][0].length, equals(135));
    });
  });

  test('loadOpenpose with default components builds 137 points', () {
    final frame = {
      'people': [
        {
          'pose_keypoints_2d': List.filled(25 * 3, 0.0),
          'face_keypoints_2d': List.filled(70 * 3, 0.0),
          'hand_left_keypoints_2d': List.filled(21 * 3, 0.0),
          'hand_right_keypoints_2d': List.filled(21 * 3, 0.0),
        }
      ]
    };
    final Pose pose = loadOpenpose({0: frame});
    expect(pose.header.components.length, equals(4));
    expect(pose.body.data[0][0].length, equals(137));
  });

  test('loadAlphapose builds a 133-point pose', () {
    final List<num> kp = List<num>.filled(133 * 3, 0.0);
    kp[0] = 1; // x of point 0
    kp[1] = 2; // y
    kp[2] = 0.9; // confidence
    final Pose pose = loadAlphapose([kp]);
    expect(pose.body.data[0][0].length, equals(133));
    expect(pose.body.data[0][0][0], equals([1, 2]));
    expect((pose.body.confidence[0][0][0] as num), equals(0.9));
    expect(detectKnownPoseFormat(pose.header),
        equals(KnownPoseFormat.alphapose133));
  });
}
