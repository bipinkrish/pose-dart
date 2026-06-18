import 'dart:io';
import 'package:pose/pose.dart';
import 'package:test/test.dart';

void main() {
  Pose readPose() =>
      Pose.read(File('test/data/mediapipe.pose').readAsBytesSync());

  test('poseInfo summarizes header and body', () {
    final String info = poseInfo(readPose());
    expect(info, contains('PoseHeader'));
    expect(info, contains('POSE_LANDMARKS'));
    expect(info, contains('FPS: 24'));
    expect(info, contains('Frames: 170'));
  });

  group('savePng', () {
    test('single frame produces a valid PNG', () async {
      final PoseVisualizer v = PoseVisualizer(readPose());
      final bytes = await v.generatePng(v.draw(maxFrames: 1));
      // PNG signature: 89 50 4E 47
      expect(bytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));
    });

    test('multiple frames produce APNG and write to disk', () async {
      final PoseVisualizer v = PoseVisualizer(readPose());
      final Directory dir = Directory.systemTemp.createTempSync('png_test');
      try {
        final File f =
            await v.savePng('${dir.path}/out.png', v.draw(maxFrames: 3));
        expect(f.existsSync(), isTrue);
        final bytes = f.readAsBytesSync();
        expect(bytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));
        // APNG has an acTL chunk
        final String ascii = String.fromCharCodes(bytes.take(200));
        expect(ascii.contains('acTL'), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}
