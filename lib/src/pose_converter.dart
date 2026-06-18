import 'dart:math' as math;
import 'package:pose/src/pose.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/src/pose_header.dart';

/// MediaPipe hand landmark names (`HandLandmark` enum order, 21 points).
const List<String> holisticHandPoints = [
  'WRIST',
  'THUMB_CMC', 'THUMB_MCP', 'THUMB_IP', 'THUMB_TIP',
  'INDEX_FINGER_MCP', 'INDEX_FINGER_PIP', 'INDEX_FINGER_DIP',
  'INDEX_FINGER_TIP',
  'MIDDLE_FINGER_MCP', 'MIDDLE_FINGER_PIP', 'MIDDLE_FINGER_DIP',
  'MIDDLE_FINGER_TIP',
  'RING_FINGER_MCP', 'RING_FINGER_PIP', 'RING_FINGER_DIP', 'RING_FINGER_TIP',
  'PINKY_MCP', 'PINKY_PIP', 'PINKY_DIP', 'PINKY_TIP', //
];

/// OpenPose hand keypoint names (21 points), positionally aligned with
/// [holisticHandPoints].
const List<String> openposeHandPoints = [
  'BASE',
  'T_STT', 'T_BCMC', 'T_MCP', 'T_IP',
  'I_CMC', 'I_MCP', 'I_PIP', 'I_DIP',
  'M_CMC', 'M_MCP', 'M_PIP', 'M_DIP',
  'R_CMC', 'R_MCP', 'R_PIP', 'R_DIP',
  'P_CMC', 'P_MCP', 'P_PIP', 'P_DIP', //
];

/// One mapped point: a component name and either a single point name (String)
/// or a list of names to average (`List<String>`).
typedef _MapPoint = (String, Object);

List<List<_MapPoint>> _handMap(String openposeComp, String holisticComp) => [
      for (int i = 0; i < holisticHandPoints.length; i++)
        [
          (openposeComp, openposeHandPoints[i]),
          (holisticComp, holisticHandPoints[i])
        ]
    ];

const List<List<_MapPoint>> _bodyMap = [
  [('pose_keypoints_2d', 'Nose'), ('POSE_LANDMARKS', 'NOSE')],
  [
    ('pose_keypoints_2d', 'Neck'),
    ('POSE_LANDMARKS', ['RIGHT_SHOULDER', 'LEFT_SHOULDER'])
  ],
  [('pose_keypoints_2d', 'RShoulder'), ('POSE_LANDMARKS', 'RIGHT_SHOULDER')],
  [('pose_keypoints_2d', 'RElbow'), ('POSE_LANDMARKS', 'RIGHT_ELBOW')],
  [('pose_keypoints_2d', 'RWrist'), ('POSE_LANDMARKS', 'RIGHT_WRIST')],
  [('pose_keypoints_2d', 'LShoulder'), ('POSE_LANDMARKS', 'LEFT_SHOULDER')],
  [('pose_keypoints_2d', 'LElbow'), ('POSE_LANDMARKS', 'LEFT_ELBOW')],
  [('pose_keypoints_2d', 'LWrist'), ('POSE_LANDMARKS', 'LEFT_WRIST')],
  [
    ('pose_keypoints_2d', 'MidHip'),
    ('POSE_LANDMARKS', ['RIGHT_HIP', 'LEFT_HIP'])
  ],
  [('pose_keypoints_2d', 'RHip'), ('POSE_LANDMARKS', 'RIGHT_HIP')],
  [('pose_keypoints_2d', 'RKnee'), ('POSE_LANDMARKS', 'RIGHT_KNEE')],
  [('pose_keypoints_2d', 'RAnkle'), ('POSE_LANDMARKS', 'RIGHT_ANKLE')],
  [('pose_keypoints_2d', 'LHip'), ('POSE_LANDMARKS', 'LEFT_HIP')],
  [('pose_keypoints_2d', 'LKnee'), ('POSE_LANDMARKS', 'LEFT_KNEE')],
  [('pose_keypoints_2d', 'LAnkle'), ('POSE_LANDMARKS', 'LEFT_ANKLE')],
  [('pose_keypoints_2d', 'REye'), ('POSE_LANDMARKS', 'RIGHT_EYE')],
  [('pose_keypoints_2d', 'LEye'), ('POSE_LANDMARKS', 'LEFT_EYE')],
  [('pose_keypoints_2d', 'REar'), ('POSE_LANDMARKS', 'RIGHT_EAR')],
  [('pose_keypoints_2d', 'LEar'), ('POSE_LANDMARKS', 'LEFT_EAR')],
  [('pose_keypoints_2d', 'LHeel'), ('POSE_LANDMARKS', 'LEFT_HEEL')],
  [('pose_keypoints_2d', 'RHeel'), ('POSE_LANDMARKS', 'RIGHT_HEEL')],
];

List<List<_MapPoint>> get _posesMap => [
      ..._handMap('hand_left_keypoints_2d', 'LEFT_HAND_LANDMARKS'),
      ..._handMap('hand_right_keypoints_2d', 'RIGHT_HAND_LANDMARKS'),
      ..._bodyMap,
    ];

/// Converts [pose] to the structure defined by [poseComponents], mapping points
/// by name via the OpenPose/Holistic correspondence table. Unmapped target
/// points are left at zero. Mirrors Python `convert_pose`.
Pose convertPose(Pose pose, List<PoseHeaderComponent> poseComponents) {
  final PoseHeader newHeader =
      PoseHeader(pose.header.version, pose.header.dimensions, poseComponents);

  final List srcData = pose.body.data as List;
  final int frames = srcData.length;
  final int people = frames > 0 ? (srcData[0] as List).length : 0;
  final int totalPoints = newHeader.totalPoints();
  final int newDims = poseComponents[0].format.length - 1;

  final List data = List.generate(
      frames,
      (_) => List.generate(
          people,
          (_) => List.generate(
              totalPoints, (_) => List<double>.filled(newDims, 0))));
  final List conf = List.generate(frames,
      (_) => List.generate(people, (_) => List<double>.filled(totalPoints, 0)));

  final Set<String> originalComponents =
      pose.header.components.map((c) => c.name).toSet();
  final Set<String> newComponents = poseComponents.map((c) => c.name).toSet();

  // new (component, point) -> original (component, point|points)
  final Map<(String, String), (String, Object)> mapping = {};
  for (final List<_MapPoint> group in _posesMap) {
    (String, Object)? originalPoint;
    (String, String)? newPoint;
    for (final (String comp, Object point) in group) {
      if (originalComponents.contains(comp)) originalPoint = (comp, point);
      if (newComponents.contains(comp) && point is String) {
        newPoint = (comp, point);
      }
    }
    if (originalPoint != null && newPoint != null) {
      mapping[newPoint] = originalPoint;
    }
  }

  final int dims = math.min(poseComponents[0].format.length,
          pose.header.components[0].format.length) -
      1;

  mapping.forEach((newPoint, originalPoint) {
    final (String c1, String p1) = newPoint;
    final (String c2, Object p2raw) = originalPoint;
    final List<String> p2names =
        p2raw is String ? [p2raw] : (p2raw as List).cast<String>();
    try {
      final List<int> p2indices = [
        for (final String p in p2names) pose.header.getPointIndex(c2, p)
      ];
      final int p1index = newHeader.getPointIndex(c1, p1);
      for (int f = 0; f < frames; f++) {
        for (int p = 0; p < people; p++) {
          for (int k = 0; k < dims; k++) {
            double sum = 0;
            for (final int idx in p2indices) {
              sum += (srcData[f][p][idx][k] as num).toDouble();
            }
            data[f][p][p1index][k] = sum / p2indices.length;
          }
          double cs = 0;
          for (final int idx in p2indices) {
            cs += (pose.body.confidence[f][p][idx] as num).toDouble();
          }
          conf[f][p][p1index] = cs / p2indices.length;
        }
      }
    } on ArgumentError {
      // point not present in one of the headers — skip
    }
  });

  return Pose(newHeader, PoseBody(pose.body.fps, data, conf));
}
