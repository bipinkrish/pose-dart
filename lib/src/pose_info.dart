import 'package:pose/src/pose.dart';

/// Returns a human-readable summary of a [pose]'s header and body (mirrors the
/// Python `pose_info` CLI output).
String poseInfo(Pose pose) {
  final header = pose.header;
  final body = pose.body;
  final List data = body.data as List;
  final int frames = data.length;
  final int people = frames > 0 ? (data[0] as List).length : 0;

  final StringBuffer sb = StringBuffer();
  sb.writeln('PoseHeader (v${header.version})');
  sb.writeln('  Dimensions: ${header.dimensions.width} x '
      '${header.dimensions.height} x ${header.dimensions.depth}');
  sb.writeln('  Components: ${header.components.length}, '
      'total points: ${header.totalPoints()}, dims: ${header.numDims()}');
  for (final c in header.components) {
    sb.writeln('    - ${c.name}: ${c.points.length} points, '
        '${c.limbs.length} limbs, format ${c.format}');
  }
  sb.writeln('PoseBody');
  sb.writeln('  FPS: ${body.fps}');
  sb.writeln('  Frames: $frames, People: $people');
  sb.writeln('  Duration: ${frames / body.fps} s');
  return sb.toString();
}
