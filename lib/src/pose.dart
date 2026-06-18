import 'dart:typed_data';
import 'package:pose/src/pose_header.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/reader.dart';
import 'package:pose/writer.dart';

/// Class representing a pose.
///
/// This class contains a pose header and pose body.
class Pose {
  final PoseHeader header;
  final PoseBody body;

  /// Constructor for Pose.
  ///
  /// Takes [header] and [body] as parameters.
  Pose(this.header, this.body);

  /// Reads a Pose from the buffer.
  ///
  /// Optionally restricts the frames read with [startFrame]/[endFrame] (frame
  /// indices) or [startTime]/[endTime] (milliseconds). Frame and time bounds
  /// are mutually exclusive per side, matching the Python implementation.
  /// Returns a Pose instance.
  static Pose read(
    Uint8List buffer, {
    int? startFrame,
    int? endFrame,
    num? startTime,
    num? endTime,
  }) {
    if (startTime != null && startFrame != null) {
      throw ArgumentError("Cannot specify both startTime and startFrame");
    }
    if (endTime != null && endFrame != null) {
      throw ArgumentError("Cannot specify both endTime and endFrame");
    }

    final BufferReader reader = BufferReader(buffer);
    final PoseHeader header = PoseHeader.read(reader);
    final PoseBody body = PoseBody.read(header, reader, {
      'startFrame': startFrame,
      'endFrame': endFrame,
      'startTime': startTime,
      'endTime': endTime,
    });

    return Pose(header, body);
  }

  /// Writes this pose to a byte buffer in the latest `.pose` format (v0.2).
  ///
  /// Returns the encoded bytes, suitable for writing to a file.
  Uint8List write() {
    final int headerDims = header.numDims();
    final int bodyDims = _bodyDims();
    if (headerDims != bodyDims) {
      throw ArgumentError(
          "Header has $headerDims dimensions, but body has $bodyDims");
    }

    final BufferWriter writer = BufferWriter();
    header.write(writer);
    body.write(writer);
    return writer.toBytes();
  }

  /// Number of spatial dimensions in the body data ([frames][people][points][dims]).
  int _bodyDims() {
    final dynamic data = body.data;
    if (data is List &&
        data.isNotEmpty &&
        data[0] is List &&
        data[0].isNotEmpty &&
        data[0][0] is List &&
        data[0][0].isNotEmpty &&
        data[0][0][0] is List) {
      return (data[0][0][0] as List).length;
    }
    throw ArgumentError("Body data should have 4 dimensions");
  }
}
