import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  Pose getPose(String filePath) {
    File file = File(filePath);
    Uint8List fileContent = file.readAsBytesSync();
    return Pose.read(fileContent);
  }

  group('Pose tests', () {
    test("Mediapipe", () {
      Pose pose = getPose("test/data/mediapipe.pose");
      expect(pose.body.fps, equals(24.0));
    });
    test("Mediapipe long", () {
      Pose pose = getPose("test/data/mediapipe_long.pose");
      expect(pose.body.fps, equals(24.0));
    });
    test("Mediapipe hand normalized", () {
      Pose pose = getPose("test/data/mediapipe_hand_normalized.pose");
      expect(pose.body.fps, equals(24.0));
    });
    test("Mediapipe long hand normalized", () {
      Pose pose = getPose("test/data/mediapipe_long_hand_normalized.pose");
      expect(pose.body.fps, equals(24.0));
    });
  });
}
