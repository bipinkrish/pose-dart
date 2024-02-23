import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';
import 'package:pose/src/pose_visualizer.dart';
import 'package:test/test.dart';

void main() {
  Pose getPose(String filePath) {
    File file = File(filePath);
    Uint8List fileContent = file.readAsBytesSync();
    return Pose.read(fileContent);
  }

  group('Visualization Tests', () {
    test("Mediapipe", () {
      Pose pose = getPose("test/data/mediapipe.pose");
      PoseVisualizer p = PoseVisualizer(pose);
      p.saveGif("test.gif");
    });
  });
}
