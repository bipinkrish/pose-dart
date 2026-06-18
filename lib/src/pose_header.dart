import 'dart:math';
import 'package:pose/reader.dart';
import 'package:pose/writer.dart';
import 'package:pose/numdart.dart';

/// Current `.pose` file format version written by [PoseHeader.write].
///
/// Matches Python `pose_format`'s `VERSION` constant: writing always emits the
/// latest (v0.2) format regardless of the version a pose was read from.
const double poseVersion = 0.2;

/// Class representing a component of a pose header.
///
/// This class contains information about the points, limbs, colors, and format of a pose header component.
class PoseHeaderComponent {
  final String name;
  final List<String> points;
  final List<Point<int>> limbs;
  final List<List<dynamic>> colors;
  final String format;
  late List<int?> relativeLimbs;

  /// Constructor for PoseHeaderComponent.
  ///
  /// Takes [name], [points], [limbs], [colors], and [format] as parameters.
  PoseHeaderComponent(
      this.name, this.points, this.limbs, this.colors, this.format) {
    relativeLimbs = getRelativeLimbs();
  }

  /// Reads a PoseHeaderComponent from the reader based on the specified version.
  ///
  /// Takes [version] and [reader] as parameters.
  /// Returns a PoseHeaderComponent instance.
  static PoseHeaderComponent read(double version, BufferReader reader) {
    final String name = reader.unpackStr();
    final String pointFormat = reader.unpackStr();
    final int pointsCount = reader.unpack(ConstStructs.ushort);
    final int limbsCount = reader.unpack(ConstStructs.ushort);
    final int colorsCount = reader.unpack(ConstStructs.ushort);
    final List<String> points =
        List.generate(pointsCount, (_) => reader.unpackStr());
    final List<Point<int>> limbs = List.generate(
        limbsCount,
        (_) => Point<int>(reader.unpack(ConstStructs.ushort),
            reader.unpack(ConstStructs.ushort)));
    final List<List<dynamic>> colors = List.generate(
      colorsCount,
      (_) => [
        reader.unpack(ConstStructs.ushort),
        reader.unpack(ConstStructs.ushort),
        reader.unpack(ConstStructs.ushort)
      ],
    );

    return PoseHeaderComponent(name, points, limbs, colors, pointFormat);
  }

  /// Calculates the relative limbs for the component.
  ///
  /// Returns a list of relative limbs.
  List<int?> getRelativeLimbs() {
    final Map<int, int> limbsMap = {};
    for (int i = 0; i < limbs.length; i++) {
      limbsMap[limbs[i].y] = i;
    }
    return limbs.map((limb) => limbsMap[limb.x]).toList();
  }

  /// Writes this component to the [writer].
  void write(BufferWriter writer) {
    writer.packStr(name); // Component name
    writer.packStr(format); // Point format
    // Lengths of points, limbs, and colors
    writer.packUShorts([points.length, limbs.length, colors.length]);

    for (final String p in points) {
      writer.packStr(p); // Names of points
    }
    for (final Point<int> limb in limbs) {
      writer.packUShorts([limb.x, limb.y]); // Indexes of limbs
    }
    for (final List<dynamic> color in colors) {
      writer.packUShorts(
          [color[0] as int, color[1] as int, color[2] as int]); // RGB colors
    }
  }
}

/// Class representing dimensions of a pose header.
///
/// This class contains information about the width, height, and depth of a pose header.
class PoseHeaderDimensions {
  final int width;
  final int height;
  final int depth;

  /// Constructor for PoseHeaderDimensions.
  ///
  /// Takes [width], [height], and [depth] as parameters.
  PoseHeaderDimensions(this.width, this.height, this.depth);

  /// Reads PoseHeaderDimensions from the reader based on the specified version.
  ///
  /// Takes [version] and [reader] as parameters.
  /// Returns a PoseHeaderDimensions instance.
  static PoseHeaderDimensions read(double version, BufferReader reader) {
    final int width = reader.unpack(ConstStructs.ushort);
    final int height = reader.unpack(ConstStructs.ushort);
    final int depth = reader.unpack(ConstStructs.ushort);

    return PoseHeaderDimensions(width, height, depth);
  }

  /// Writes these dimensions to the [writer] as three unsigned shorts.
  ///
  /// Throws [ArgumentError] if any value is outside the 0..65535 range.
  void write(BufferWriter writer) {
    const int maxUShort = 0xFFFF;
    if (width < 0 || width > maxUShort) {
      throw ArgumentError("Width must be between 0 and 65535. Got $width");
    }
    if (height < 0 || height > maxUShort) {
      throw ArgumentError("Height must be between 0 and 65535. Got $height");
    }
    if (depth < 0 || depth > maxUShort) {
      throw ArgumentError("Depth must be between 0 and 65535. Got $depth");
    }
    writer.packUShorts([width, height, depth]);
  }
}

/// Class representing a pose header.
///
/// This class contains information about the version, dimensions, components, and bounding box status of a pose header.
class PoseHeader {
  final double version;
  final PoseHeaderDimensions dimensions;
  final List<PoseHeaderComponent> components;
  final bool isBbox;

  /// Constructor for PoseHeader.
  ///
  /// Takes [version], [dimensions], [components], and [isBbox] as parameters.
  PoseHeader(this.version, this.dimensions, this.components,
      {this.isBbox = false});

  /// Reads a PoseHeader from the reader.
  ///
  /// Takes [reader] as a parameter.
  /// Returns a PoseHeader instance.
  static PoseHeader read(BufferReader reader) {
    final double version = reader.unpack(ConstStructs.float);
    final PoseHeaderDimensions dimensions =
        PoseHeaderDimensions.read(version, reader);
    final int componentsCount = reader.unpack(ConstStructs.ushort);
    final List<PoseHeaderComponent> components = List.generate(
        componentsCount, (_) => PoseHeaderComponent.read(version, reader));

    return PoseHeader(version, dimensions, components);
  }

  /// Writes this header to the [writer].
  ///
  /// Always writes the latest format version ([poseVersion]), matching the
  /// Python implementation.
  void write(BufferWriter writer) {
    writer.packFloat(poseVersion); // File version
    dimensions.write(writer); // Width, height, depth
    writer.packUShort(components.length); // Number of components
    for (final PoseHeaderComponent component in components) {
      component.write(writer);
    }
  }

  /// Total number of points across all components.
  int totalPoints() =>
      components.map((c) => c.points.length).fold(0, (a, b) => a + b);

  /// Number of spatial dimensions (X, Y, Z, ...) excluding confidence.
  int numDims() => components.map((c) => c.format.length).reduce(max) - 1;
}
