import 'dart:io';
import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  test('convertPose maps holistic body points to an openpose layout', () {
    final Pose pose =
        Pose.read(File('test/data/mediapipe.pose').readAsBytesSync());

    // Target: an openpose body component with a few mappable points.
    final target = PoseHeaderComponent(
      'pose_keypoints_2d',
      ['RShoulder', 'LShoulder', 'Neck'],
      <Point<int>>[],
      <List<dynamic>>[],
      'XYC',
    );
    final Pose converted = convertPose(pose, [target]);

    expect(converted.header.components.length, equals(1));
    expect(converted.body.data[0][0].length, equals(3));

    final int rShoulder =
        pose.header.getPointIndex('POSE_LANDMARKS', 'RIGHT_SHOULDER');
    final int lShoulder =
        pose.header.getPointIndex('POSE_LANDMARKS', 'LEFT_SHOULDER');

    // RShoulder maps directly to RIGHT_SHOULDER (x, y).
    for (int k = 0; k < 2; k++) {
      expect(
          (converted.body.data[0][0][0][k] as num).toDouble(),
          closeTo(
              (pose.body.data[0][0][rShoulder][k] as num).toDouble(), 1e-6));
    }

    // Neck maps to the mean of the two shoulders.
    final double expectedNeckX = ((pose.body.data[0][0][rShoulder][0] as num) +
            (pose.body.data[0][0][lShoulder][0] as num)) /
        2;
    expect((converted.body.data[0][0][2][0] as num).toDouble(),
        closeTo(expectedNeckX.toDouble(), 1e-6));
  });
}
