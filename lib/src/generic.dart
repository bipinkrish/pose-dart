import 'dart:math' as math;
import 'package:pose/src/masked_array.dart';
import 'package:pose/src/normalization_3d.dart';
import 'package:pose/src/pose.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/src/pose_formats.dart';
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
enum KnownPoseFormat { holistic, openpose, openpose135, alphapose133 }

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
    if (name == 'BODY_133') return KnownPoseFormat.alphapose133;
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
    case KnownPoseFormat.alphapose133:
      return (
        (c: 'BODY_133', p: 'right_shoulder'),
        (c: 'BODY_133', p: 'left_shoulder')
      );
  }
}

/// Default normalization info (distance between the two shoulders) for a known
/// pose format.
PoseNormalizationInfo poseNormalizationInfo(PoseHeader header) {
  final (r, l) = poseShoulders(header);
  return header.normalizationInfo(p1: (r.c, r.p), p2: (l.c, l.p));
}

/// Names of all components in the header.
List<String> getComponentNames(PoseHeader header) =>
    [for (final c in header.components) c.name];

/// Rescales a pose to a fixed [targetWidth], centering on the shoulders, and
/// updates the header width/height. Mutates and returns the pose.
Pose normalizePoseSize(Pose pose, {int targetWidth = 512}) {
  const double shift = 1.25;
  final double shoulderWidth = (targetWidth / shift) / 2;
  pose.body.data =
      pose.body.maskedData.add(shift).multiply(shoulderWidth).toNested();
  pose.header.dimensions = PoseHeaderDimensions(
      targetWidth, targetWidth, pose.header.dimensions.depth);
  return pose;
}

/// Per-format leg point names to drop in [poseHideLegs].
Map<String, List<String>> _legPointsToRemove(Pose pose) {
  switch (detectKnownPoseFormat(pose.header)) {
    case KnownPoseFormat.holistic:
      const List<String> names = ['KNEE', 'ANKLE', 'HEEL', 'FOOT_INDEX', 'HIP'];
      final List<String> toRemove = [
        for (final s in ['LEFT', 'RIGHT'])
          for (final n in names) '${s}_$n'
      ];
      return {
        'POSE_LANDMARKS': toRemove,
        'POSE_WORLD_LANDMARKS': toRemove,
      };
    case KnownPoseFormat.openpose:
      const List<String> words = [
        'Hip',
        'Knee',
        'Ankle',
        'BigToe',
        'SmallToe',
        'Heel'
      ];
      final List<String> bodyPoints = pose.header.components
          .firstWhere((c) => c.name == 'pose_keypoints_2d')
          .points;
      return {
        'pose_keypoints_2d': [
          for (final p in bodyPoints)
            if (words.any((w) => p.contains(w))) p
        ]
      };
    case KnownPoseFormat.openpose135:
    case KnownPoseFormat.alphapose133:
      throw UnsupportedError('poseHideLegs is not supported for this format');
  }
}

/// Hides (zeros out) or, if [remove] is true, removes the leg points.
Pose poseHideLegs(Pose pose, {bool remove = false}) {
  final Map<String, List<String>> pointsToRemove = _legPointsToRemove(pose);
  if (remove) {
    return pose.removeComponents([], pointsToRemove: pointsToRemove);
  }

  final List<int> indices = [];
  pointsToRemove.forEach((component, points) {
    for (final String point in points) {
      try {
        indices.add(pose.header.getPointIndex(component, point));
      } on ArgumentError {
        // point not present (e.g. removed earlier) — skip
      }
    }
  });

  final List data = pose.body.data as List;
  final List confidence = pose.body.confidence;
  final int dims = (data[0][0][0] as List).length;
  for (int f = 0; f < data.length; f++) {
    for (int p = 0; p < (data[f] as List).length; p++) {
      for (final int i in indices) {
        data[f][p][i] = List<double>.filled(dims, 0);
        confidence[f][p][i] = 0.0;
      }
    }
  }
  return pose;
}

/// Flat index of a hand's wrist point.
int getHandWristIndex(Pose pose, String hand) {
  switch (detectKnownPoseFormat(pose.header)) {
    case KnownPoseFormat.holistic:
      return pose.header
          .getPointIndex('${hand.toUpperCase()}_HAND_LANDMARKS', 'WRIST');
    case KnownPoseFormat.openpose:
      return pose.header
          .getPointIndex('hand_${hand.toLowerCase()}_keypoints_2d', 'BASE');
    case KnownPoseFormat.openpose135:
    case KnownPoseFormat.alphapose133:
      throw UnsupportedError('getHandWristIndex unsupported for this format');
  }
}

/// Flat index of the body's wrist point for the given hand.
int getBodyHandWristIndex(Pose pose, String hand) {
  switch (detectKnownPoseFormat(pose.header)) {
    case KnownPoseFormat.holistic:
      return pose.header
          .getPointIndex('POSE_LANDMARKS', '${hand.toUpperCase()}_WRIST');
    case KnownPoseFormat.openpose:
      return pose.header
          .getPointIndex('pose_keypoints_2d', '${hand.toUpperCase()[0]}Wrist');
    case KnownPoseFormat.openpose135:
    case KnownPoseFormat.alphapose133:
      throw UnsupportedError(
          'getBodyHandWristIndex unsupported for this format');
  }
}

/// Replaces the body wrist with the (more accurate) hand wrist where the hand
/// wrist is confident. [hand] is `"LEFT"` or `"RIGHT"`. Returns a new pose.
Pose correctWrist(Pose pose, String hand) {
  pose = pose.copy();
  final int wristIndex = getHandWristIndex(pose, hand);
  final int bodyWristIndex = getBodyHandWristIndex(pose, hand);

  final List data = pose.body.data as List;
  final List confidence = pose.body.confidence;
  for (int f = 0; f < data.length; f++) {
    for (int p = 0; p < (data[f] as List).length; p++) {
      final num wristConf = confidence[f][p][wristIndex] as num;
      final List chosenData = wristConf == 0
          ? data[f][p][bodyWristIndex] as List
          : data[f][p][wristIndex] as List;
      data[f][p][bodyWristIndex] = [...chosenData];
      confidence[f][p][bodyWristIndex] =
          wristConf == 0 ? confidence[f][p][bodyWristIndex] : wristConf;
    }
  }
  return pose;
}

/// Applies [correctWrist] to both hands.
Pose correctWrists(Pose pose) =>
    correctWrist(correctWrist(pose, 'LEFT'), 'RIGHT');

/// Hardcoded MediaPipe `FACEMESH_CONTOURS` point indices (kept by
/// [reduceHolistic]) — avoids a mediapipe dependency.
const List<String> _faceContours = [
  '0', '7', '10', '13', '14', '17', '21', '33', '37', '39', '40', '46', '52',
  '53', '54', '55', '58', '61', '63', '65', '66', '67', '70', '78', '80', '81',
  '82', '84', '87', '88', '91', '93', '95', '103', '105', '107', '109', '127',
  '132', '133', '136', '144', '145', '146', '148', '149', '150', '152', '153',
  '154', '155', '157', '158', '159', '160', '161', '162', '163', '172', '173',
  '176', '178', '181', '185', '191', '234', '246', '249', '251', '263', '267',
  '269', '270', '276', '282', '283', '284', '285', '288', '291', '293', '295',
  '296', '297', '300', '308', '310', '311', '312', '314', '317', '318', '321',
  '323', '324', '332', '334', '336', '338', '356', '361', '362', '365', '373',
  '374', '375', '377', '378', '379', '380', '381', '382', '384', '385', '386',
  '387', '388', '389', '390', '397', '398', '400', '402', '405', '409', '415',
  '454', '466' //
];

/// Reduces a holistic pose to face contours and a body without face/hand/leg
/// points (drops `POSE_WORLD_LANDMARKS`). Non-holistic poses are returned as-is.
Pose reduceHolistic(Pose pose) {
  if (detectKnownPoseFormat(pose.header) != KnownPoseFormat.holistic) {
    return pose;
  }
  const List<String> ignoreNames = [
    'EAR', 'NOSE', 'MOUTH', 'EYE', // face
    'THUMB', 'PINKY', 'INDEX', // hands
    'KNEE', 'ANKLE', 'HEEL', 'FOOT_INDEX' // feet
  ];

  final List<String> bodyPoints = pose.header.components
      .firstWhere((c) => c.name == 'POSE_LANDMARKS')
      .points;
  final List<String> bodyNoFaceNoHands = [
    for (final p in bodyPoints)
      if (ignoreNames.every((i) => !p.contains(i))) p
  ];

  final List<String> components = [
    for (final c in pose.header.components)
      if (c.name != 'POSE_WORLD_LANDMARKS') c.name
  ];
  return pose.getComponents(components, points: {
    'FACE_LANDMARKS': _faceContours,
    'POSE_LANDMARKS': bodyNoFaceNoHands,
  });
}

double _randn(math.Random r) {
  final double u1 = 1 - r.nextDouble();
  final double u2 = r.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Builds a random pose with the given [components] (Gaussian-noise data and
/// confidence), useful for tests. Mirrors Python `fake_pose` but requires
/// [components] explicitly (the large standard landmark tables are not bundled).
Pose fakePose(int numFrames,
    {int numPeople = 1,
    double fps = 25.0,
    required List<PoseHeaderComponent> components,
    math.Random? rng}) {
  final math.Random r = rng ?? math.Random();
  final String fmt = components[0].format;
  final PoseHeaderDimensions dimensions;
  if (fmt == 'XYZC') {
    dimensions = PoseHeaderDimensions(1, 1, 1);
  } else if (fmt == 'XYC') {
    dimensions = PoseHeaderDimensions(1, 1, 0);
  } else {
    throw ArgumentError('Unknown point format: $fmt');
  }

  final PoseHeader header = PoseHeader(0.2, dimensions, components);
  final int totalPoints = header.totalPoints();
  final int numDims = header.numDims();

  final List data = [
    for (int f = 0; f < numFrames; f++)
      [
        for (int p = 0; p < numPeople; p++)
          [
            for (int n = 0; n < totalPoints; n++)
              [for (int d = 0; d < numDims; d++) _randn(r)]
          ]
      ]
  ];
  final List confidence = [
    for (int f = 0; f < numFrames; f++)
      [
        for (int p = 0; p < numPeople; p++)
          [for (int n = 0; n < totalPoints; n++) _randn(r)]
      ]
  ];
  return Pose(header, PoseBody(fps, data, confidence));
}

/// Hand component references for 3D normalization: `(hands, plane, line)` where
/// `hands` is `(left, right)`, `plane` is three point names and `line` two.
((String, String), (String, String, String), (String, String)) handsComponents(
    PoseHeader header) {
  switch (detectKnownPoseFormat(header)) {
    case KnownPoseFormat.holistic:
      return (
        ('LEFT_HAND_LANDMARKS', 'RIGHT_HAND_LANDMARKS'),
        ('WRIST', 'PINKY_MCP', 'INDEX_FINGER_MCP'),
        ('WRIST', 'MIDDLE_FINGER_MCP')
      );
    case KnownPoseFormat.openpose:
      return (
        ('hand_left_keypoints_2d', 'hand_right_keypoints_2d'),
        ('BASE', 'P_CMC', 'I_CMC'),
        ('BASE', 'M_CMC')
      );
    case KnownPoseFormat.openpose135:
    case KnownPoseFormat.alphapose133:
      throw UnsupportedError('handsComponents unsupported for this format');
  }
}

/// Normalizes one component in 3D and appends the normalized points to the
/// pose body (matching Python: the header is left unchanged). Mutates [pose].
void normalizeComponent3d(Pose pose, String componentName,
    (String, String, String) plane, (String, String) line) {
  final Pose handPose = pose.getComponents([componentName]);
  final PoseNormalizationInfo planeInfo = handPose.header.normalizationInfo(
    p1: (componentName, plane.$1),
    p2: (componentName, plane.$2),
    p3: (componentName, plane.$3),
  );
  final PoseNormalizationInfo lineInfo = handPose.header.normalizationInfo(
    p1: (componentName, line.$1),
    p2: (componentName, line.$2),
  );

  final PoseNormalizer normalizer =
      PoseNormalizer(plane: planeInfo, line: lineInfo);
  final List normData = normalizer(handPose.body.maskedData).toNested() as List;
  final List handConf = handPose.body.confidence;

  final List data = pose.body.data as List;
  final List conf = pose.body.confidence;
  pose.body.data = [
    for (int f = 0; f < data.length; f++)
      [
        for (int p = 0; p < (data[f] as List).length; p++)
          [...(data[f][p] as List), ...(normData[f][p] as List)]
      ]
  ];
  pose.body.confidence = [
    for (int f = 0; f < conf.length; f++)
      [
        for (int p = 0; p < (conf[f] as List).length; p++)
          [...(conf[f][p] as List), ...(handConf[f][p] as List)]
      ]
  ];
}

/// 3D-normalizes the hand components, appending normalized points to the body.
void normalizeHands3d(Pose pose,
    {bool leftHand = true, bool rightHand = true}) {
  final (hands, plane, line) = handsComponents(pose.header);
  if (leftHand) normalizeComponent3d(pose, hands.$1, plane, line);
  if (rightHand) normalizeComponent3d(pose, hands.$2, plane, line);
}

/// Returns the standard component table for a known pose [format].
List<PoseHeaderComponent> getStandardComponentsForKnownFormat(
    KnownPoseFormat format) {
  switch (format) {
    case KnownPoseFormat.holistic:
      return holisticComponents();
    case KnownPoseFormat.openpose:
      return openposeComponents();
    case KnownPoseFormat.openpose135:
      return openpose135Components();
    case KnownPoseFormat.alphapose133:
      return alphapose133Components();
  }
}

/// Random holistic pose (POSE/FACE/hands/WORLD landmarks) for tests/demos.
Pose fakeHolisticPose(int numFrames,
        {int numPeople = 1, double fps = 25.0, math.Random? rng}) =>
    fakePose(numFrames,
        numPeople: numPeople,
        fps: fps,
        components: holisticComponents(),
        rng: rng);

/// Random OpenPose (137-point) pose for tests/demos.
Pose fakeOpenposePose(int numFrames,
        {int numPeople = 1, double fps = 25.0, math.Random? rng}) =>
    fakePose(numFrames,
        numPeople: numPeople,
        fps: fps,
        components: openposeComponents(),
        rng: rng);

/// Random OpenPose-135 pose for tests/demos.
Pose fakeOpenpose135Pose(int numFrames,
        {int numPeople = 1, double fps = 25.0, math.Random? rng}) =>
    fakePose(numFrames,
        numPeople: numPeople,
        fps: fps,
        components: openpose135Components(),
        rng: rng);
