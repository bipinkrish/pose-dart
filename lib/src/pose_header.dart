import 'dart:math';

import 'package:pose/utils/reader.dart';
import 'package:pose/numdart.dart';

class PoseHeaderComponent {
  final String name;
  final List<String> points;
  final List<Point<int>> limbs;
  final List<List<dynamic>> colors;
  final String format;
  late List<int?> relativeLimbs;

  PoseHeaderComponent(
      this.name, this.points, this.limbs, this.colors, this.format) {
    relativeLimbs = getRelativeLimbs();
  }

  static PoseHeaderComponent read(double version, BufferReader reader) {
    String name = reader.unpackStr();
    String pointFormat = reader.unpackStr();
    int pointsCount = reader.unpack(ConstStructs.ushort);
    int limbsCount = reader.unpack(ConstStructs.ushort);
    int colorsCount = reader.unpack(ConstStructs.ushort);
    List<String> points = List.generate(pointsCount, (_) => reader.unpackStr());
    List<Point<int>> limbs = List.generate(
        limbsCount,
        (_) => Point<int>(reader.unpack(ConstStructs.ushort),
            reader.unpack(ConstStructs.ushort)));
    List<List<dynamic>> colors = List.generate(
      colorsCount,
      (_) => [
        reader.unpack(ConstStructs.ushort),
        reader.unpack(ConstStructs.ushort),
        reader.unpack(ConstStructs.ushort)
      ],
    );

    return PoseHeaderComponent(name, points, limbs, colors, pointFormat);
  }

  List<int?> getRelativeLimbs() {
    Map<int, int> limbsMap = {};
    for (int i = 0; i < limbs.length; i++) {
      limbsMap[limbs[i].y] = i;
    }
    return limbs.map((limb) => limbsMap[limb.x]).toList();
  }
}

class PoseHeaderDimensions {
  final int width;
  final int height;
  final int depth;

  PoseHeaderDimensions(this.width, this.height, this.depth);

  static PoseHeaderDimensions read(double version, BufferReader reader) {
    int width = reader.unpack(ConstStructs.ushort);
    int height = reader.unpack(ConstStructs.ushort);
    int depth = reader.unpack(ConstStructs.ushort);

    return PoseHeaderDimensions(width, height, depth);
  }
}

class PoseHeader {
  final double version;
  final PoseHeaderDimensions dimensions;
  final List<PoseHeaderComponent> components;
  final bool isBbox;

  PoseHeader(this.version, this.dimensions, this.components,
      {this.isBbox = false});

  static PoseHeader read(BufferReader reader) {
    double version = reader.unpack(ConstStructs.float);
    PoseHeaderDimensions dimensions =
        PoseHeaderDimensions.read(version, reader);
    int componentsCount = reader.unpack(ConstStructs.ushort);
    List<PoseHeaderComponent> components = List.generate(
        componentsCount, (_) => PoseHeaderComponent.read(version, reader));

    return PoseHeader(version, dimensions, components);
  }
}
