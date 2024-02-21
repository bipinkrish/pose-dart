// ignore_for_file: non_constant_identifier_names, no_leading_underscores_for_local_identifiers, prefer_typing_uninitialized_variables

import 'package:pose/src/pose_header.dart';
import 'package:pose/utils/reader.dart';
import 'package:pose/numdart.dart';

/// Class representing a pose body.
///
/// This class provides functionality to read pose body data.
class PoseBody {
  static final String tensorReader = 'ABSTRACT-DO-NOT-USE';

  final double fps;
  final dynamic data;
  final List<dynamic> confidence;

  /// Constructor for PoseBody.
  ///
  /// Takes [fps], [data], and [confidence] as parameters.
  PoseBody(this.fps, this.data, this.confidence);

  /// Reads pose body data based on the provided header and reader.
  ///
  /// Returns a PoseBody instance.
  static PoseBody read(
      PoseHeader header, BufferReader reader, Map<String, dynamic> kwargs) {
    if ((header.version * 1000).round() == 100) {
      return read_v0_1(header, reader, kwargs);
    }

    throw UnimplementedError("Unknown version - ${header.version}");
  }

  /// Reads pose body data for version 0.1.
  ///
  /// Takes [header], [reader], and [kwargs] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1(
      PoseHeader header, BufferReader reader, Map<String, dynamic> kwargs) {
    int fps, _frames;
    fps = reader.unpack(ConstStructs.double_ushort)[0];

    _frames = reader.unpack(ConstStructs.ushort);
    int _people = reader.unpack(ConstStructs.ushort);
    if (_people == 0) {
      _people = 1;
    }
    int _points =
        header.components.map((c) => c.points.length).reduce((a, b) => a + b);
    int _dims = header.components
            .map((c) => c.format.length)
            .reduce((a, b) => a > b ? a : b) -
        1;
    _frames = reader.bytesLeft() ~/ (_people * _points * (_dims + 1) * 4);

    var data = read_v0_1_frames(_frames, [_people, _points, _dims], reader,
        kwargs['startFrame'], kwargs['endFrame']);
    var confidence = read_v0_1_frames(_frames, [_people, _points], reader,
        kwargs['startFrame'], kwargs['endFrame']);

    return PoseBody(fps.toDouble(), data, confidence);
  }

  /// Reads pose body data for version 0.1 frames.
  ///
  /// Takes [frames], [shape], [reader], [startFrame], and [endFrame] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1_frames(int frames, List<int> shape,
      BufferReader reader, int? startFrame, int? endFrame) {
    var tensorReader = reader.unpackNum;
    var s = ConstStructs.float;

    int _frames = frames;
    if (startFrame != null && startFrame > 0) {
      if (startFrame >= frames) {
        throw ArgumentError("Start frame is greater than the number of frames");
      }
      reader.advance(s, (startFrame * shape.reduce((a, b) => a * b)));
      _frames -= startFrame;
    }

    int removeFrames = 0;
    if (endFrame != null) {
      endFrame = endFrame > frames ? frames : endFrame;
      removeFrames = frames - endFrame;
      _frames -= removeFrames;
    }

    var tensor = tensorReader(ConstStructs.float, [_frames, ...shape]);

    if (removeFrames != 0) {
      reader.advance(s, (removeFrames * shape.reduce((a, b) => a * b)));
    }

    return tensor;
  }
}
