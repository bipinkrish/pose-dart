import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  PoseHeaderComponent body() => PoseHeaderComponent(
        'pose_keypoints_2d',
        ['A', 'B'],
        <Point<int>>[],
        <List<dynamic>>[],
        'XYC',
      );

  test('loadOpenpose parses keypoints and confidence', () {
    final frames = {
      0: {
        'people': [
          {
            'pose_keypoints_2d': [1, 2, 0.9, 3, 4, 0.8]
          }
        ]
      },
      1: {
        'people': [
          {
            'pose_keypoints_2d': [5, 6, 0.7, 7, 8, 0.0]
          }
        ]
      },
    };

    final Pose pose = loadOpenpose(frames, [body()], width: 100, height: 100);

    expect((pose.body.data as List).length, equals(2)); // frames
    expect(pose.body.data[0][0].length, equals(2)); // points
    expect(pose.body.data[0][0][0], equals([1, 2]));
    expect(pose.body.data[0][0][1], equals([3, 4]));
    expect((pose.body.confidence[0][0][0] as num), equals(0.9));
    expect(pose.body.data[1][0][1], equals([7, 8]));
    expect((pose.body.confidence[1][0][1] as num), equals(0.0));
    expect(pose.header.components[0].name, equals('pose_keypoints_2d'));
  });

  test('loadOpenposeDirectory reads *_keypoints.json files', () {
    final Directory dir = Directory.systemTemp.createTempSync('openpose_test');
    try {
      File('${dir.path}/cam_000000000000_keypoints.json')
          .writeAsStringSync(jsonEncode({
        'people': [
          {
            'pose_keypoints_2d': [1, 1, 1.0, 2, 2, 1.0]
          }
        ]
      }));
      File('${dir.path}/cam_000000000001_keypoints.json')
          .writeAsStringSync(jsonEncode({
        'people': [
          {
            'pose_keypoints_2d': [3, 3, 1.0, 4, 4, 1.0]
          }
        ]
      }));

      final Pose pose = loadOpenposeDirectory(dir.path, [body()]);
      expect((pose.body.data as List).length, equals(2));
      expect(pose.body.data[1][0][0], equals([3, 3]));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
