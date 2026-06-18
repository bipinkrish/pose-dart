import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';
import 'package:pose/src/pose_header.dart';
import 'package:pose/writer.dart';
import 'package:test/test.dart';

/// Recursively compares two nested numeric structures within [eps].
void expectNestedClose(dynamic a, dynamic b, {double eps = 1e-3}) {
  if (a is List && b is List) {
    expect(a.length, equals(b.length), reason: 'list length mismatch');
    for (int i = 0; i < a.length; i++) {
      expectNestedClose(a[i], b[i], eps: eps);
    }
  } else if (a is num && b is num) {
    expect(a.toDouble(), closeTo(b.toDouble(), eps));
  } else {
    fail('Type mismatch comparing $a (${a.runtimeType}) and $b (${b.runtimeType})');
  }
}

void main() {
  Pose getPose(String filePath) {
    final Uint8List bytes = File(filePath).readAsBytesSync();
    return Pose.read(bytes);
  }

  void expectHeadersEqual(PoseHeader a, PoseHeader b) {
    expect(b.dimensions.width, equals(a.dimensions.width));
    expect(b.dimensions.height, equals(a.dimensions.height));
    expect(b.dimensions.depth, equals(a.dimensions.depth));
    expect(b.components.length, equals(a.components.length));
    for (int i = 0; i < a.components.length; i++) {
      final PoseHeaderComponent ca = a.components[i];
      final PoseHeaderComponent cb = b.components[i];
      expect(cb.name, equals(ca.name));
      expect(cb.format, equals(ca.format));
      expect(cb.points, equals(ca.points));
      expect(cb.limbs.length, equals(ca.limbs.length));
      for (int j = 0; j < ca.limbs.length; j++) {
        expect(cb.limbs[j].x, equals(ca.limbs[j].x));
        expect(cb.limbs[j].y, equals(ca.limbs[j].y));
      }
      expect(cb.colors, equals(ca.colors));
    }
  }

  group('Round-trip write tests', () {
    final List<String> fixtures = [
      'test/data/mediapipe.pose', // v0.1
      'test/data/mediapipe_hand_normalized.pose', // v0.1
      'test/data/four-v0.2.pose', // v0.2
    ];

    for (final String path in fixtures) {
      test('read -> write -> read preserves $path', () {
        final Pose original = getPose(path);
        final Uint8List written = original.write();
        final Pose reloaded = Pose.read(written);

        // Writing always emits the latest format version. (float32 round-off
        // makes the read-back value ~0.20000000298.)
        expect(reloaded.header.version, closeTo(0.2, 1e-6));

        expectHeadersEqual(original.header, reloaded.header);
        expect(reloaded.body.fps, closeTo(original.body.fps.toDouble(), 1e-6));
        expectNestedClose(reloaded.body.data, original.body.data);
        expectNestedClose(reloaded.body.confidence, original.body.confidence);
      });
    }

    test('written bytes start with version 0.2 header', () {
      final Pose original = getPose('test/data/mediapipe.pose');
      final Uint8List written = original.write();
      final double version =
          ByteData.sublistView(written).getFloat32(0, Endian.little);
      expect(version, closeTo(0.2, 1e-6));
    });
  });

  group('Read slicing', () {
    test('startFrame/endFrame restricts frame count', () {
      final Uint8List bytes = File('test/data/mediapipe.pose').readAsBytesSync();
      final Pose full = Pose.read(bytes);
      final int total = (full.body.data as List).length;

      final Pose sliced = Pose.read(bytes, startFrame: 5, endFrame: 15);
      expect((sliced.body.data as List).length, equals(10));
      expect((sliced.body.confidence as List).length, equals(10));
      expect(total, greaterThan(15));
    });

    test('startTime/startFrame are mutually exclusive', () {
      final Uint8List bytes = File('test/data/mediapipe.pose').readAsBytesSync();
      expect(() => Pose.read(bytes, startFrame: 1, startTime: 100),
          throwsArgumentError);
    });
  });

  group('v0.0 reading', () {
    test('reads interleaved coords + confidence, keeps first person', () {
      // Hand-build a minimal v0.0 buffer: 1 component, 2 points, format "XYC"
      // (2 dims + confidence), 2 frames, 1 person each.
      final BufferWriter w = BufferWriter();
      // --- header ---
      w.packFloat(0.0); // version 0.0
      w.packUShorts([100, 200, 0]); // width, height, depth
      w.packUShort(1); // 1 component
      w.packStr('test'); // component name
      w.packStr('XYC'); // point format -> 2 dims + confidence
      w.packUShorts([2, 0, 0]); // points, limbs, colors
      w.packStr('p0');
      w.packStr('p1');
      // --- body (v0.0) ---
      w.packUShorts([24, 2]); // double_ushort: fps, frames
      // frame 0: 1 person
      w.packUShort(1); // people
      w.packUShort(0); // person id (skipped, 2 bytes)
      w.packFloats([
        [1.0, 2.0, 0.9], // p0: x, y, conf
        [3.0, 4.0, 0.8], // p1
      ]);
      // frame 1: 1 person
      w.packUShort(1);
      w.packUShort(0);
      w.packFloats([
        [5.0, 6.0, 0.7],
        [7.0, 8.0, 0.6],
      ]);

      final Pose pose = Pose.read(w.toBytes());

      expect(pose.header.version, closeTo(0.0, 1e-6));
      expect(pose.body.fps, equals(24.0));

      final List data = pose.body.data as List;
      final List conf = pose.body.confidence as List;
      // shape: (frames=2, people=1, points=2, dims=2)
      expect((data.length, data[0].length, data[0][0].length, data[0][0][0].length),
          equals((2, 1, 2, 2)));
      expectNestedClose(data[0][0], [
        [1.0, 2.0],
        [3.0, 4.0]
      ]);
      expectNestedClose(conf[0][0], [0.9, 0.8]);
      expectNestedClose(data[1][0], [
        [5.0, 6.0],
        [7.0, 8.0]
      ]);
      expectNestedClose(conf[1][0], [0.7, 0.6]);
    });
  });
}
