import 'package:pose/src/pose.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/src/pose_formats.dart';
import 'package:pose/src/pose_header.dart';

/// Loads AlphaPose WholeBody keypoints into a [Pose].
///
/// [framesKeypoints] is one flat `[x, y, c, x, y, c, ...]` list per frame
/// (single person). [components] defaults to the WholeBody-133 layout
/// ([alphapose133Components]); pass your own for the 136-point variant.
Pose loadAlphapose(
  List<List<num>> framesKeypoints, {
  List<PoseHeaderComponent>? components,
  double fps = 24,
  int width = 1000,
  int height = 1000,
  int depth = 0,
}) {
  components ??= alphapose133Components();
  final PoseHeader header =
      PoseHeader(0.2, PoseHeaderDimensions(width, height, depth), components);
  final int totalPoints = header.totalPoints();

  final List data = [
    for (final List<num> kp in framesKeypoints)
      [
        [
          for (int n = 0; n < totalPoints; n++)
            [kp[n * 3].toDouble(), kp[n * 3 + 1].toDouble()]
        ]
      ]
  ];
  final List confidence = [
    for (final List<num> kp in framesKeypoints)
      [
        [for (int n = 0; n < totalPoints; n++) kp[n * 3 + 2].toDouble()]
      ]
  ];

  return Pose(header, PoseBody(fps, data, confidence));
}
