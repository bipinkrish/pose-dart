// ignore_for_file: unused_local_variable

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

  group('Visualization Tests', () {
    test("Mediapipe", () async {
      try {
        Pose pose = getPose("test/data/mediapipe.pose");
        PoseVisualizer p = PoseVisualizer(pose);
        File file = await p.saveGif("test/test.gif", p.draw());
        expect(file.existsSync(), true);
        File expectedFile = File("test/data/test.gif");
        expect(file.readAsBytesSync(), expectedFile.readAsBytesSync());
      } catch (e) {
        Error();
      }
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
