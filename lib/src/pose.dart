import 'dart:typed_data';

import 'package:pose/src/pose_header.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/utils/reader.dart';

class Pose {
  PoseHeader header;
  PoseBody body;

  Pose(this.header, this.body);

  static Pose read(Uint8List buffer) {
    BufferReader reader = BufferReader(buffer);
    PoseHeader header = PoseHeader.read(reader);
    PoseBody body = PoseBody.read(header, reader, {});

    return Pose(header, body);
  }
}
