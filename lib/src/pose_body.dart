// ignore_for_file: non_constant_identifier_names, no_leading_underscores_for_local_identifiers, prefer_typing_uninitialized_variables

import 'package:pose/src/pose_header.dart';
import 'package:pose/reader.dart';
import 'package:pose/writer.dart';
import 'package:pose/numdart.dart';

/// Class representing a pose body.
///
/// This class provides functionality to read pose body data.
class PoseBody {
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
    final int version_hundred = (header.version * 1000).round();
    if (version_hundred == 0) {
      return read_v0_0(header, reader, kwargs);
    }
    if (version_hundred == 100 || version_hundred == 200) {
      return read_v0_1(header, reader, version_hundred, kwargs);
    }

    throw UnimplementedError("Unknown version - ${header.version}");
  }

  /// Reads pose body data for version 0.0.
  ///
  /// In v0.0 each frame stores a variable number of people, and each point's
  /// coordinates and confidence are interleaved (the last value of every
  /// point's format is its confidence). Only the first person is kept, mirroring
  /// the Python implementation.
  static PoseBody read_v0_0(
      PoseHeader header, BufferReader reader, Map<String, dynamic> kwargs) {
    final List<dynamic> fpsFrames = reader.unpack(ConstStructs.double_ushort);
    final int fps = fpsFrames[0];
    final int frames = fpsFrames[1];

    final int dims = header.numDims();
    final int points = header.totalPoints();

    final List framesData = [];
    final List framesConfidence = [];

    for (int f = 0; f < frames; f++) {
      final int people = reader.unpack(ConstStructs.ushort);
      List? person0Data;
      List? person0Confidence;

      for (int pid = 0; pid < people; pid++) {
        reader.advance(ConstStructs.short); // Skip person ID
        final List personData = [];
        final List personConfidence = [];

        for (final PoseHeaderComponent component in header.components) {
          final int fmtLen = component.format.length;
          final List pts = reader.unpackNum(
              ConstStructs.float, [component.points.length, fmtLen]);
          for (final dynamic pt in pts) {
            personData.add((pt as List).sublist(0, fmtLen - 1));
            personConfidence.add(pt[fmtLen - 1]);
          }
        }

        if (pid == 0) {
          person0Data = personData;
          person0Confidence = personConfidence;
        }
      }

      // In case there is no person, fill with zeros.
      person0Data ??= List.generate(points, (_) => List.filled(dims, 0.0));
      person0Confidence ??= List.filled(points, 0.0);

      framesData.add([person0Data]);
      framesConfidence.add([person0Confidence]);
    }

    return PoseBody(fps.toDouble(), framesData, framesConfidence);
  }

  /// Reads pose body data for version 0.1 and 0.2.
  ///
  /// Takes [header], [reader], [version], and [kwargs] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1(PoseHeader header, BufferReader reader, int version,
      Map<String, dynamic> kwargs) {
    late int fps, _frames;
    if (version == 100) {
      final List<dynamic> lst = reader.unpack(ConstStructs.double_ushort);
      fps = lst[0];
      _frames = lst[1];
    } else {
      // version == 200
      fps = reader.unpack(ConstStructs.float).toInt();
      _frames = reader.unpack(ConstStructs.float).toInt();
    }
    final int _people = reader.unpack(ConstStructs.ushort);

    final int _points =
        header.components.map((c) => c.points.length).reduce((a, b) => a + b);
    final int _dims = header.components
            .map((c) => c.format.length)
            .reduce((a, b) => a > b ? a : b) -
        1;
    _frames = reader.bytesLeft() ~/ (_people * _points * (_dims + 1) * 4);

    // Resolve frame slicing, allowing start/end to be given either as frame
    // indices or as times in milliseconds.
    int? startFrame = kwargs['startFrame'] as int?;
    int? endFrame = kwargs['endFrame'] as int?;
    final num? startTime = kwargs['startTime'] as num?;
    final num? endTime = kwargs['endTime'] as num?;
    if (startTime != null) {
      startFrame = (startTime / 1000 * fps).floor();
    }
    if (endTime != null) {
      endFrame = (endTime / 1000 * fps).ceil();
    }

    final List data = read_v0_1_frames(
        _frames, [_people, _points, _dims], reader, startFrame, endFrame);
    final List confidence = read_v0_1_frames(
        _frames, [_people, _points], reader, startFrame, endFrame);

    return PoseBody(fps.toDouble(), data, confidence);
  }

  /// Writes this pose body to the [writer] using the v0.2 format
  /// (float fps, uint frame count, ushort people count, then float32 data and
  /// float32 confidence). Mirrors the Python implementation, which always
  /// emits the latest format.
  void write(BufferWriter writer) {
    final int frames = data.length;
    final int people = frames > 0 ? (data[0] as List).length : 0;

    writer.packFloat(fps);
    writer.packUInt(frames);
    writer.packUShort(people);
    writer.packFloats(data);
    writer.packFloats(confidence);
  }

  /// Reads pose body data for version 0.1 and 0.2 frames.
  ///
  /// Takes [frames], [shape], [reader], [startFrame], and [endFrame] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1_frames(int frames, List<int> shape,
      BufferReader reader, int? startFrame, int? endFrame) {
    final Struct s = ConstStructs.float;
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

    final List tensor =
        reader.unpackNum(ConstStructs.float, [_frames, ...shape]);
    if (removeFrames != 0) {
      reader.advance(s, (removeFrames * shape.reduce((a, b) => a * b)));
    }

    return tensor;
  }
}
