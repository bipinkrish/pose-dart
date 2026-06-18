import 'package:pose/src/masked_array.dart';
import 'package:pose/src/pose_header.dart';

/// Computes the Euclidean distance between two sets of points along the last
/// dimension (mirrors Python `pose_format.utils.fast_math.distance_batch`).
///
/// Both inputs share a shape `(..., dims)`; the result drops the last axis.
MaskedArray distanceBatch(MaskedArray p1s, MaskedArray p2s) {
  final MaskedArray diff = p1s.subtract(p2s);
  final MaskedArray squared = diff.multiply(diff);
  return squared.sum({squared.ndim - 1}).sqrt();
}

/// Recognized pose formats (subset of the Python library that is detectable
/// from component names without native dependencies).
enum KnownPoseFormat { holistic, openpose, openpose135 }

const List<String> _holisticComponents = [
  'POSE_LANDMARKS',
  'FACE_LANDMARKS',
  'LEFT_HAND_LANDMARKS',
  'RIGHT_HAND_LANDMARKS',
  'POSE_WORLD_LANDMARKS',
];

const List<String> _openposeComponents = [
  'pose_keypoints_2d',
  'face_keypoints_2d',
  'hand_left_keypoints_2d',
  'hand_right_keypoints_2d',
];

/// Detects the pose format from the header's component names.
///
/// Throws [UnsupportedError] if the schema is not recognized.
KnownPoseFormat detectKnownPoseFormat(PoseHeader header) {
  final List<String> names = [for (final c in header.components) c.name];
  for (final String name in names) {
    if (_holisticComponents.contains(name)) return KnownPoseFormat.holistic;
    if (_openposeComponents.contains(name)) return KnownPoseFormat.openpose;
    if (name == 'BODY_135') return KnownPoseFormat.openpose135;
  }
  throw UnsupportedError(
      'Could not detect pose format from components: $names');
}

/// Returns the `(component, point)` references for the right and left shoulders.
(({String c, String p}), ({String c, String p})) poseShoulders(
    PoseHeader header) {
  switch (detectKnownPoseFormat(header)) {
    case KnownPoseFormat.holistic:
      return (
        (c: 'POSE_LANDMARKS', p: 'RIGHT_SHOULDER'),
        (c: 'POSE_LANDMARKS', p: 'LEFT_SHOULDER')
      );
    case KnownPoseFormat.openpose135:
      return ((c: 'BODY_135', p: 'RShoulder'), (c: 'BODY_135', p: 'LShoulder'));
    case KnownPoseFormat.openpose:
      return (
        (c: 'pose_keypoints_2d', p: 'RShoulder'),
        (c: 'pose_keypoints_2d', p: 'LShoulder')
      );
  }
}

/// Default normalization info (distance between the two shoulders) for a known
/// pose format.
PoseNormalizationInfo poseNormalizationInfo(PoseHeader header) {
  final (r, l) = poseShoulders(header);
  return header.normalizationInfo(p1: (r.c, r.p), p2: (l.c, l.p));
}
