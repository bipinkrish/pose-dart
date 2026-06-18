import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';

/// CLI: prints a summary of a `.pose` file.
///
/// Usage: `dart run pose:pose_info <file.pose>`
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: pose_info <file.pose>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final Uint8List bytes = file.readAsBytesSync();
  final Pose pose = Pose.read(bytes);
  stdout.write(poseInfo(pose));
}
