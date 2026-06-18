import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:pose/src/pose.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/src/pose_header.dart';

/// Loads OpenPose-style keypoint [frames] into a [Pose].
///
/// [frames] maps a frame index to a decoded OpenPose JSON object of the form
/// `{"people": [{"<component>": [x, y, c, ...]}, ...]}`. [components] describes
/// the layout (names must match the JSON keys; point counts must match) — pass
/// your own so the large built-in OpenPose tables aren't required.
Pose loadOpenpose(
  Map<int, dynamic> frames,
  List<PoseHeaderComponent> components, {
  double fps = 24,
  int width = 1000,
  int height = 1000,
  int depth = 0,
  int? numFrames,
}) {
  final PoseHeader header =
      PoseHeader(0.2, PoseHeaderDimensions(width, height, depth), components);
  final int totalPoints = header.totalPoints();
  final int dims = components[0].format.length - 1;

  final int nf = numFrames ?? (frames.keys.reduce(max) + 1);
  final int people = frames.values
      .map((f) => (f['people'] as List).length)
      .fold(0, (a, b) => a > b ? a : b);

  final List data = List.generate(
      nf,
      (_) => List.generate(
          people,
          (_) =>
              List.generate(totalPoints, (_) => List<double>.filled(dims, 0))));
  final List confidence = List.generate(nf,
      (_) => List.generate(people, (_) => List<double>.filled(totalPoints, 0)));

  frames.forEach((frameId, frame) {
    final List peopleList = frame['people'] as List;
    for (int personId = 0; personId < peopleList.length; personId++) {
      final Map person = peopleList[personId] as Map;
      int keypointId = 0;
      for (final PoseHeaderComponent component in components) {
        final List numbers = person[component.name] as List;
        final int step = component.format.length;
        for (int k = 0; k + step - 1 < numbers.length; k += step) {
          for (int d = 0; d < dims; d++) {
            data[frameId][personId][keypointId][d] =
                (numbers[k + d] as num).toDouble();
          }
          confidence[frameId][personId][keypointId] =
              (numbers[k + dims] as num).toDouble();
          keypointId++;
        }
      }
    }
  });

  return Pose(header, PoseBody(fps, data, confidence));
}

/// Extracts the frame id from an OpenPose filename like
/// `prefix_000000000017_keypoints.json` (the last numeric group before
/// `_keypoints`).
int getFrameId(String filename, RegExp pattern) {
  final List<RegExpMatch> matches = pattern.allMatches(filename).toList();
  return int.parse(matches.last.group(1)!);
}

/// Loads a directory of OpenPose `*_keypoints.json` files into a [Pose].
/// [components] is supplied by the caller (see [loadOpenpose]).
Pose loadOpenposeDirectory(
  String directory,
  List<PoseHeaderComponent> components, {
  double fps = 24,
  int width = 1000,
  int height = 1000,
  int depth = 0,
  int? numFrames,
  RegExp? pattern,
}) {
  final RegExp pat = pattern ?? RegExp(r'(\d+)_keypoints');
  final Map<int, dynamic> frames = {};
  for (final FileSystemEntity entry in Directory(directory).listSync()) {
    if (entry is File && entry.path.endsWith('.json')) {
      final String name = entry.uri.pathSegments.last;
      if (pat.allMatches(name).isEmpty) continue;
      frames[getFrameId(name, pat)] = jsonDecode(entry.readAsStringSync());
    }
  }
  return loadOpenpose(frames, components,
      fps: fps,
      width: width,
      height: height,
      depth: depth,
      numFrames: numFrames);
}
