import 'dart:math';
import 'dart:typed_data';
import 'package:pose/src/pose_header.dart';
import 'package:pose/src/pose_body.dart';
import 'package:pose/src/masked_array.dart';
import 'package:pose/src/generic.dart';
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

  /// Deep copy of this pose.
  Pose copy() => Pose(header, body.copy());

  /// Returns a new pose where each component is reduced to its bounding box
  /// (`TOP_LEFT`/`BOTTOM_RIGHT`).
  Pose bbox() => Pose(header.bbox(), body.bbox(header));

  @override
  String toString() => 'Pose(\n  $header\n  $body\n)';

  /// Shifts the pose so its minimum is at the origin and resizes the header
  /// dimensions to fit. Mutates this pose.
  void focus() {
    final MaskedArray d = body.maskedData;
    final MaskedArray mins = d.min({0, 1, 2}); // (dims,)
    final MaskedArray maxs = d.max({0, 1, 2});

    final List minVals = mins.toNested() as List;
    if (minVals.any((v) => (v as num) != 0)) {
      body.data = d.subtract(mins).toNested();
    }

    final List range = maxs.subtract(mins).toNested() as List;
    int dimAt(int i) => i < range.length ? (range[i] as num).ceil() : 0;
    header.dimensions = PoseHeaderDimensions(dimAt(0), dimAt(1), dimAt(2));
  }

  /// Normalizes points to a fixed distance between two points (defaults to the
  /// shoulders for known formats). Mutates and returns this pose.
  Pose normalize({PoseNormalizationInfo? info, double scaleFactor = 1}) {
    info ??= poseNormalizationInfo(header);

    final MaskedArray d = body.maskedData;
    final MaskedArray transposed =
        d.permute(pointsDims); // (points,people,frames,dims)
    final MaskedArray p1s = transposed.takeFirst(info.p1);
    final MaskedArray p2s = transposed.takeFirst(info.p2);

    // Move points so the center of p1/p2 is at the origin.
    final MaskedArray center = p2s.add(p1s).divide(2).mean({0, 1});

    final double meanDistance = distanceBatch(p1s, p2s).mean().scalar;
    final double scale = scaleFactor / meanDistance;

    body.data = d.subtract(center).multiply(scale).toNested();
    return this;
  }

  /// Normalizes the point distribution to zero mean and unit variance over
  /// [axis]. Returns the `(mean, std)` used (so they can be reapplied).
  (MaskedArray, MaskedArray) normalizeDistribution(
      {MaskedArray? mu, MaskedArray? std, Set<int> axis = const {0, 1}}) {
    final MaskedArray d = body.maskedData;
    final MaskedArray muV = mu ?? d.mean(axis);
    final MaskedArray stdV = std ?? d.std(axis);
    body.data = d.subtract(muV).divide(stdV).toNested();
    return (muV, stdV);
  }

  /// Inverse of [normalizeDistribution]. Mutates this pose.
  void unnormalizeDistribution(MaskedArray mu, MaskedArray std) {
    body.data = body.maskedData.multiply(std).add(mu).toNested();
  }

  /// Returns a new pose keeping only [components], optionally restricting each
  /// component to a subset of [points] (`{componentName: [pointNames]}`).
  Pose getComponents(List<String> components,
      {Map<String, List<String>>? points}) {
    final Map<String, List<int>> indexes = {};
    final Map<String, PoseHeaderComponent> newComponents = {};

    int idx = 0;
    for (final PoseHeaderComponent c in header.components) {
      if (components.contains(c.name)) {
        List<String> newPoints = c.points;
        List<Point<int>> newLimbs = c.limbs;

        if (points != null && points.containsKey(c.name)) {
          newPoints = points[c.name]!;
          final Map<int, int> mapping = {
            for (int i = 0; i < newPoints.length; i++)
              c.points.indexOf(newPoints[i]): i
          };
          final Set<int> oldIdx = mapping.keys.toSet();
          newLimbs = [
            for (final Point<int> limb in c.limbs)
              if (oldIdx.contains(limb.x) && oldIdx.contains(limb.y))
                Point<int>(mapping[limb.x]!, mapping[limb.y]!)
          ];
          indexes[c.name] = [
            for (final String p in newPoints) idx + c.points.indexOf(p)
          ];
        } else {
          indexes[c.name] = [for (int i = 0; i < c.points.length; i++) idx + i];
        }

        newComponents[c.name] = PoseHeaderComponent(
            c.name, newPoints, newLimbs, c.colors, c.format);
      }
      idx += c.points.length;
    }

    final List<PoseHeaderComponent> orderedComponents = [
      for (final String name in components) newComponents[name]!
    ];
    final List<int> flatIndexes = [
      for (final String name in components) ...indexes[name]!
    ];

    final PoseHeader newHeader =
        PoseHeader(header.version, header.dimensions, orderedComponents);
    final PoseBody newBody = body.getPoints(flatIndexes);
    return Pose(newHeader, newBody);
  }

  /// Returns a new pose with [componentsToRemove] removed, optionally also
  /// removing specific [pointsToRemove] (`{componentName: [pointNames]}`).
  Pose removeComponents(List<String> componentsToRemove,
      {Map<String, List<String>>? pointsToRemove}) {
    final List<String> componentsToKeep = [];
    final Map<String, List<String>> pointsDict = {};

    for (final PoseHeaderComponent c in header.components) {
      if (!componentsToRemove.contains(c.name)) {
        componentsToKeep.add(c.name);
        if (pointsToRemove != null) {
          final List<String> toRemove = pointsToRemove[c.name] ?? const [];
          pointsDict[c.name] = [
            for (final String p in c.points)
              if (!toRemove.contains(p)) p
          ];
        } else {
          pointsDict[c.name] = c.points.toList();
        }
      }
    }

    return getComponents(componentsToKeep, points: pointsDict);
  }

  /// Uniformly drops a random fraction of frames; returns the new pose and the
  /// retained frame indices.
  (Pose, List<int>) frameDropoutUniform(
      {double dropoutMin = 0.2, double dropoutMax = 1.0, Random? rng}) {
    final (PoseBody b, List<int> idx) = body.frameDropoutUniform(
        dropoutMin: dropoutMin, dropoutMax: dropoutMax, rng: rng);
    return (Pose(header, b), idx);
  }

  /// Normally drops a random fraction of frames; returns the new pose and the
  /// retained frame indices.
  (Pose, List<int>) frameDropoutNormal(
      {double dropoutMean = 0.5, double dropoutStd = 0.1, Random? rng}) {
    final (PoseBody b, List<int> idx) = body.frameDropoutNormal(
        dropoutMean: dropoutMean, dropoutStd: dropoutStd, rng: rng);
    return (Pose(header, b), idx);
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
