import 'dart:math';
import 'package:pose/src/pose_header.dart';

/// Standard pose-format component tables (point names, limbs, colors), ported
/// from the Python `pose_format.utils.*` modules.
///
/// Note on face meshes: the holistic face (MediaPipe FACEMESH, ~2600 edges) and
/// the AlphaPose face limbs are intentionally left empty — they are bulk mesh
/// data that only matters when *drawing a pose built from scratch*. Real
/// `.pose` files carry their own limbs, and the point names/counts here are
/// complete, so `fakePose`/loaders produce correctly-shaped poses.

List<Point<int>> _limbsIndex(
        List<String> points, List<(String, String)> limbs) =>
    [
      for (final (a, b) in limbs)
        Point<int>(points.indexOf(a), points.indexOf(b))
    ];

// ===========================================================================
// OpenPose (BODY_25 + face 70 + hands 21x2 = 137)
// ===========================================================================

const List<String> _opBody = [
  'Nose', 'Neck', 'RShoulder', 'RElbow', 'RWrist', 'LShoulder', 'LElbow',
  'LWrist', 'MidHip', 'RHip', 'RKnee', 'RAnkle', 'LHip', 'LKnee', 'LAnkle',
  'REye', 'LEye', 'REar', 'LEar', 'LBigToe', 'LSmallToe', 'LHeel', 'RBigToe',
  'RSmallToe', 'RHeel' //
];

const List<(String, String)> _opBodyLimbs = [
  ('Neck', 'RShoulder'), ('RShoulder', 'RElbow'), ('RElbow', 'RWrist'),
  ('Neck', 'LShoulder'), ('LShoulder', 'LElbow'), ('LElbow', 'LWrist'),
  ('Neck', 'MidHip'), ('Nose', 'LEye'), ('Nose', 'REye'), ('Nose', 'LEar'),
  ('Nose', 'REar'), ('Neck', 'Nose'), ('MidHip', 'RHip'), ('RHip', 'RKnee'),
  ('RKnee', 'RAnkle'), ('MidHip', 'LHip'), ('LHip', 'LKnee'),
  ('LKnee', 'LAnkle'), ('RAnkle', 'RHeel'), ('RAnkle', 'RBigToe'),
  ('RBigToe', 'RSmallToe'), ('LAnkle', 'LHeel'), ('LAnkle', 'LBigToe'),
  ('LBigToe', 'LSmallToe') //
];

const List<String> _opHand = [
  'BASE', 'T_STT', 'T_BCMC', 'T_MCP', 'T_IP', 'I_CMC', 'I_MCP', 'I_PIP',
  'I_DIP', 'M_CMC', 'M_MCP', 'M_PIP', 'M_DIP', 'R_CMC', 'R_MCP', 'R_PIP',
  'R_DIP', 'P_CMC', 'P_MCP', 'P_PIP', 'P_DIP' //
];

const List<(String, String)> _opHandLimbs = [
  ('BASE', 'T_STT'), ('BASE', 'I_CMC'), ('BASE', 'M_CMC'), ('BASE', 'R_CMC'),
  ('BASE', 'P_CMC'), ('T_STT', 'T_BCMC'), ('T_BCMC', 'T_MCP'),
  ('T_MCP', 'T_IP'),
  ('I_CMC', 'I_MCP'), ('I_MCP', 'I_PIP'), ('I_PIP', 'I_DIP'),
  ('M_CMC', 'M_MCP'),
  ('M_MCP', 'M_PIP'), ('M_PIP', 'M_DIP'), ('R_CMC', 'R_MCP'),
  ('R_MCP', 'R_PIP'),
  ('R_PIP', 'R_DIP'), ('P_CMC', 'P_MCP'), ('P_MCP', 'P_PIP'),
  ('P_PIP', 'P_DIP') //
];

(List<String>, List<(String, String)>) _opFace() {
  final List<String> border = [for (int i = 0; i < 17; i++) 'FB_$i'];
  final List<String> eyebrows = [for (int i = 17; i < 27; i++) 'FEB_$i'];
  final List<String> nose = [for (int i = 27; i < 36; i++) 'FN_$i'];
  final List<String> eye = [for (int i = 36; i < 48; i++) 'FE_$i'];
  final List<String> outerLips = [for (int i = 48; i < 60; i++) 'FLO_$i'];
  final List<String> innerLips = [for (int i = 60; i < 68; i++) 'FLI_$i'];
  const List<String> pupils = ['FP_68', 'FP_69'];

  final List<(String, String)> limbs = [
    for (int i = 8; i >= 1; i--) ('FB_$i', 'FB_${i - 1}'),
    for (int i = 8; i < 16; i++) ('FB_$i', 'FB_${i + 1}'),
    for (int i = 48; i < 59; i++) ('FLO_$i', 'FLO_${i + 1}'),
    ('FLO_59', 'FLO_48'),
    for (int i = 60; i < 67; i++) ('FLI_$i', 'FLI_${i + 1}'),
    ('FLI_67', 'FLI_60'),
    for (int i = 27; i < 31; i++) ('FN_$i', 'FN_${i + 1}'),
    for (int i = 31; i < 35; i++) ('FN_$i', 'FN_${i + 1}'),
    ('FN_30', 'FN_33'),
    for (int i = 17; i < 21; i++) ('FEB_$i', 'FEB_${i + 1}'),
    for (int i = 22; i < 26; i++) ('FEB_$i', 'FEB_${i + 1}'),
    for (int i = 36; i < 41; i++) ('FE_$i', 'FE_${i + 1}'),
    ('FE_41', 'FE_36'),
    for (int i = 42; i < 47; i++) ('FE_$i', 'FE_${i + 1}'),
    ('FE_47', 'FE_42'),
  ];
  return (
    [
      ...border,
      ...eyebrows,
      ...nose,
      ...eye,
      ...outerLips,
      ...innerLips,
      ...pupils
    ],
    limbs
  );
}

/// OpenPose components: `pose_keypoints_2d`, `face_keypoints_2d`,
/// `hand_left_keypoints_2d`, `hand_right_keypoints_2d` (137 points, format XYC).
List<PoseHeaderComponent> openposeComponents() {
  final (facePoints, faceLimbs) = _opFace();
  PoseHeaderComponent hand(String name) => PoseHeaderComponent(
      name,
      _opHand,
      _limbsIndex(_opHand, _opHandLimbs),
      [
        [192, 0, 0]
      ],
      'XYC');
  return [
    PoseHeaderComponent(
        'pose_keypoints_2d',
        _opBody,
        _limbsIndex(_opBody, _opBodyLimbs),
        [
          [255, 0, 0]
        ],
        'XYC'),
    PoseHeaderComponent(
        'face_keypoints_2d',
        facePoints,
        _limbsIndex(facePoints, faceLimbs),
        [
          [128, 0, 0]
        ],
        'XYC'),
    hand('hand_left_keypoints_2d'),
    hand('hand_right_keypoints_2d'),
  ];
}

// ===========================================================================
// OpenPose-135 (single BODY_135 component)
// ===========================================================================

const List<String> _op135Body = [
  'Nose', 'LEye', 'REye', 'LEar', 'REar', 'LShoulder', 'RShoulder', 'LElbow',
  'RElbow', 'LWrist', 'RWrist', 'LHip', 'RHip', 'LKnee', 'RKnee', 'LAnkle',
  'RAnkle', 'UpperNeck', 'HeadTop', 'LBigToe', 'LSmallToe', 'LHeel', 'RBigToe',
  'RSmallToe', 'RHeel' //
];

List<String> _op135Hand(String side) => [
      '${side}Thumb1CMC', '${side}Thumb2Knuckles', '${side}Thumb3IP',
      '${side}Thumb4FingerTip', '${side}Index1Knuckles', '${side}Index2PIP',
      '${side}Index3DIP', '${side}Index4FingerTip', '${side}Middle1Knuckles',
      '${side}Middle2PIP', '${side}Middle3DIP', '${side}Middle4FingerTip',
      '${side}Ring1Knuckles', '${side}Ring2PIP', '${side}Ring3DIP',
      '${side}Ring4FingerTip', '${side}Pinky1Knuckles', '${side}Pinky2PIP',
      '${side}Pinky3DIP', '${side}Pinky4FingerTip' //
    ];

const List<String> _op135Face = [
  'FaceContour0', 'FaceContour1', 'FaceContour2', 'FaceContour3',
  'FaceContour4',
  'FaceContour5', 'FaceContour6', 'FaceContour7', 'FaceContour8',
  'FaceContour9',
  'FaceContour10', 'FaceContour11', 'FaceContour12', 'FaceContour13',
  'FaceContour14', 'FaceContour15', 'FaceContour16', 'REyeBrow0', 'REyeBrow1',
  'REyeBrow2', 'REyeBrow3', 'REyeBrow4', 'LEyeBrow4', 'LEyeBrow3', 'LEyeBrow2',
  'LEyeBrow1', 'LEyeBrow0', 'NoseUpper0', 'NoseUpper1', 'NoseUpper2',
  'NoseUpper3',
  'NoseLower0', 'NoseLower1', 'NoseLower2', 'NoseLower3', 'NoseLower4', 'REye0',
  'REye1', 'REye2', 'REye3', 'REye4', 'REye5', 'LEye0', 'LEye1', 'LEye2',
  'LEye3',
  'LEye4', 'LEye5', 'OMouth0', 'OMouth1', 'OMouth2', 'OMouth3', 'OMouth4',
  'OMouth5', 'OMouth6', 'OMouth7', 'OMouth8', 'OMouth9', 'OMouth10', 'OMouth11',
  'IMouth0', 'IMouth1', 'IMouth2', 'IMouth3', 'IMouth4', 'IMouth5', 'IMouth6',
  'IMouth7', 'RPupil', 'LPupil' //
];

/// OpenPose-135 component (`BODY_135`, 135 points = body 25 + hands 20x2 + face 70).
List<PoseHeaderComponent> openpose135Components() {
  final List<String> points = [
    ..._op135Body,
    ..._op135Hand('L'),
    ..._op135Hand('R'),
    ..._op135Face
  ];
  return [
    PoseHeaderComponent(
        'BODY_135',
        points,
        const <Point<int>>[],
        [
          [255, 0, 0]
        ],
        'XYC')
  ];
}

// ===========================================================================
// Holistic (MediaPipe): POSE_LANDMARKS, FACE_LANDMARKS, hands, POSE_WORLD_LANDMARKS
// ===========================================================================

const List<String> _mpPose = [
  'NOSE', 'LEFT_EYE_INNER', 'LEFT_EYE', 'LEFT_EYE_OUTER', 'RIGHT_EYE_INNER',
  'RIGHT_EYE', 'RIGHT_EYE_OUTER', 'LEFT_EAR', 'RIGHT_EAR', 'MOUTH_LEFT',
  'MOUTH_RIGHT', 'LEFT_SHOULDER', 'RIGHT_SHOULDER', 'LEFT_ELBOW', 'RIGHT_ELBOW',
  'LEFT_WRIST', 'RIGHT_WRIST', 'LEFT_PINKY', 'RIGHT_PINKY', 'LEFT_INDEX',
  'RIGHT_INDEX', 'LEFT_THUMB', 'RIGHT_THUMB', 'LEFT_HIP', 'RIGHT_HIP',
  'LEFT_KNEE', 'RIGHT_KNEE', 'LEFT_ANKLE', 'RIGHT_ANKLE', 'LEFT_HEEL',
  'RIGHT_HEEL', 'LEFT_FOOT_INDEX', 'RIGHT_FOOT_INDEX' //
];

const List<(int, int)> _mpPoseConnections = [
  (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8), (9, 10),
  (11, 12), (11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19),
  (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20), (11, 23),
  (12, 24), (23, 24), (23, 25), (24, 26), (25, 27), (26, 28), (27, 29),
  (28, 30), (29, 31), (30, 32), (27, 31), (28, 32) //
];

const List<String> _mpHand = [
  'WRIST', 'THUMB_CMC', 'THUMB_MCP', 'THUMB_IP', 'THUMB_TIP',
  'INDEX_FINGER_MCP', 'INDEX_FINGER_PIP', 'INDEX_FINGER_DIP',
  'INDEX_FINGER_TIP',
  'MIDDLE_FINGER_MCP', 'MIDDLE_FINGER_PIP', 'MIDDLE_FINGER_DIP',
  'MIDDLE_FINGER_TIP', 'RING_FINGER_MCP', 'RING_FINGER_PIP', 'RING_FINGER_DIP',
  'RING_FINGER_TIP', 'PINKY_MCP', 'PINKY_PIP', 'PINKY_DIP', 'PINKY_TIP' //
];

const List<(int, int)> _mpHandConnections = [
  (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9),
  (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (15, 16), (13, 17),
  (17, 18), (18, 19), (19, 20), (0, 17) //
];

/// Holistic components (point format defaults to `XYZC`). The face component has
/// 468 (+`additionalFacePoints`) named points but no limbs (see file note).
List<PoseHeaderComponent> holisticComponents(
    {String pf = 'XYZC', int additionalFacePoints = 0}) {
  final List<Point<int>> poseLimbs = [
    for (final (a, b) in _mpPoseConnections) Point<int>(a, b)
  ];
  final List<Point<int>> handLimbs = [
    for (final (a, b) in _mpHandConnections) Point<int>(a, b)
  ];
  final List<String> facePoints = [
    for (int i = 0; i < 468 + additionalFacePoints; i++) '$i'
  ];

  PoseHeaderComponent hand(String name) => PoseHeaderComponent(
      name,
      _mpHand,
      handLimbs,
      [
        [0, 0, 255]
      ],
      pf);

  return [
    PoseHeaderComponent(
        'POSE_LANDMARKS',
        _mpPose,
        poseLimbs,
        [
          [255, 0, 0]
        ],
        pf),
    PoseHeaderComponent(
        'FACE_LANDMARKS',
        facePoints,
        const <Point<int>>[],
        [
          [128, 0, 0]
        ],
        pf),
    hand('LEFT_HAND_LANDMARKS'),
    hand('RIGHT_HAND_LANDMARKS'),
    PoseHeaderComponent(
        'POSE_WORLD_LANDMARKS',
        _mpPose,
        poseLimbs,
        [
          [255, 0, 0]
        ],
        pf),
  ];
}

// ===========================================================================
// AlphaPose WholeBody-133 (body 23 + face 68 + hands 21x2)
// ===========================================================================

const List<String> _apBody = [
  'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear', 'left_shoulder',
  'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist',
  'left_hip', 'right_hip', 'left_knee', 'right_knee', 'left_ankle',
  'right_ankle', 'left_big_toe', 'left_small_toe', 'left_heel', 'right_big_toe',
  'right_small_toe', 'right_heel' //
];

const List<(String, String)> _apBodyLimbs = [
  ('left_ankle', 'left_knee'), ('left_knee', 'left_hip'),
  ('right_ankle', 'right_knee'), ('right_knee', 'right_hip'),
  ('left_hip', 'right_hip'), ('left_shoulder', 'left_hip'),
  ('right_shoulder', 'right_hip'), ('left_shoulder', 'right_shoulder'),
  ('left_shoulder', 'left_elbow'), ('right_shoulder', 'right_elbow'),
  ('left_elbow', 'left_wrist'), ('right_elbow', 'right_wrist'),
  ('left_eye', 'right_eye'), ('nose', 'left_eye'), ('nose', 'right_eye'),
  ('left_eye', 'left_ear'), ('right_eye', 'right_ear'),
  ('left_ear', 'left_shoulder'), ('right_ear', 'right_shoulder'),
  ('left_ankle', 'left_big_toe'), ('left_ankle', 'left_small_toe'),
  ('left_ankle', 'left_heel'), ('right_ankle', 'right_big_toe'),
  ('right_ankle', 'right_small_toe'), ('right_ankle', 'right_heel') //
];

List<(String, String)> _apHandLimbs() => [
      for (final base in [0, 5, 9, 13, 17]) ('hand_0', 'hand_$base'),
      for (final start in [1, 5, 9, 13, 17])
        for (int i = start; i < start + 3; i++) ('hand_$i', 'hand_${i + 1}'),
    ];

/// AlphaPose WholeBody-133 components (`BODY_133`, `FACE_133`, `LEFT_HAND_133`,
/// `RIGHT_HAND_133`). Face limbs are omitted (see file note).
List<PoseHeaderComponent> alphapose133Components() {
  final List<String> face = [for (int i = 0; i < 68; i++) 'face_$i'];
  final List<String> hand = [for (int i = 0; i < 21; i++) 'hand_$i'];
  final List<Point<int>> handLimbs = _limbsIndex(hand, _apHandLimbs());
  return [
    PoseHeaderComponent(
        'BODY_133',
        _apBody,
        _limbsIndex(_apBody, _apBodyLimbs),
        [
          [0, 255, 0]
        ],
        'XYC'),
    PoseHeaderComponent(
        'FACE_133',
        face,
        const <Point<int>>[],
        [
          [255, 255, 255]
        ],
        'XYC'),
    PoseHeaderComponent(
        'LEFT_HAND_133',
        hand,
        handLimbs,
        [
          [0, 255, 0]
        ],
        'XYC'),
    PoseHeaderComponent(
        'RIGHT_HAND_133',
        hand,
        handLimbs,
        [
          [255, 128, 0]
        ],
        'XYC'),
  ];
}
