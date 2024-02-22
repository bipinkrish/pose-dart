// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart';
import 'package:pose/pose.dart';
import 'package:pose/numdart.dart' as nd;
import 'package:pose/numdart.dart' show MaskedArray;
import 'package:tuple/tuple.dart';

class PoseVisualizer {
  Pose pose;
  int? thickness;
  double poseFps;
  Image? background;

  PoseVisualizer(this.pose, {this.thickness, required this.poseFps});

  Image _drawFrame(MaskedArray frame, List frameConfidence, Image img) {
    Pixel backgroundColor = img.getPixel(0, 0);
    var t = thickness ?? (sqrt(img.width * img.height) / 150).round();
    var radius = (t / 2).round();

    for (var i = 0; i < frame.data.length; i++) {
      List person = frame.data[i];
      var personConfidence = frameConfidence[i];
      var c = personConfidence;

      List<Tuple2<int, int>> points2D = List<Tuple2<int, int>>.from(
          person.map((p) => Tuple2<int, int>(p[0], p[1])));

      int idx = 0;
      for (var component in pose.header.components) {
        var colors = component.colors
            .map((c) => img.getColor(c[0], c[1], c[2]))
            .toList();

        List<num> _pointColor(int pI) {
          var opacity = c[pI + idx];
          var npColor = [
            (pI % colors.length) * opacity + (1 - opacity) * backgroundColor.r,
            (pI % colors.length) * opacity + (1 - opacity) * backgroundColor.g,
            (pI % colors.length) * opacity + (1 - opacity) * backgroundColor.b,
          ];
          return npColor;
        }

        for (var i = 0; i < component.points.length; i++) {
          if (c[i + idx] > 0) {
            var p = points2D[i + idx];

            drawCircle(img,
                x: p.item1,
                y: p.item2,
                radius: radius,
                color: ColorFloat16.fromList(
                    _pointColor(i).map((num n) => n.toDouble()).toList()));
          }
        }

        if (pose.header.isBbox) {
          var point1 = points2D[0 + idx];
          var point2 = points2D[1 + idx];
          var color = Tuple3<int, int, int>(
            (colors[0].r + colors[1].r) ~/ 2,
            (colors[0].g + colors[1].g) ~/ 2,
            (colors[0].b + colors[1].b) ~/ 2,
          );

          drawRect(img,
              x1: point1.item1,
              y1: point1.item2,
              x2: point2.item1,
              y2: point2.item2,
              color: ColorFloat16.rgb(color.item1, color.item2, color.item3),
              thickness: t);
        } else {
          for (var limb in component.limbs) {
            if (c[limb.x + idx] > 0 && c[limb.y + idx] > 0) {
              Tuple2<int, int> point1 = points2D[limb.x + idx];
              Tuple2<int, int> point2 = points2D[limb.y + idx];

              Tuple3<double, double, double> color =
                  Tuple3<double, double, double>.fromList(nd.mean(
                      [_pointColor(limb.x), _pointColor(limb.y)],
                      axis: 0));

              drawLine(img,
                  x1: point1.item1,
                  y1: point1.item2,
                  x2: point2.item1,
                  y2: point2.item2,
                  color:
                      ColorFloat16.rgb(color.item1, color.item2, color.item3),
                  thickness: t);
            }
          }
        }

        idx += component.points.length;
      }
    }

    return img;
  }

  Iterable<Image> draw(
      {List<int> backgroundColor = const [255, 255, 255],
      int? maxFrames}) sync* {
    var intFrames = MaskedArray(pose.body.data, []).round();
    background = Image(
        width: pose.header.dimensions.width,
        height: pose.header.dimensions.height)
      ..clear(ColorFloat16.rgb(
          backgroundColor[0], backgroundColor[1], backgroundColor[2]));

    for (var i = 0;
        i < min(intFrames.length, maxFrames ?? intFrames.length);
        i++) {
      yield _drawFrame(MaskedArray(intFrames[i], []), pose.body.confidence[i],
          background!.clone());
    }
  }

  void saveGif(String fileName, Iterable<Image> frames, double poseFps) {
    GifEncoder encoder = GifEncoder(delay: 0, repeat: 0);
    int frameDuration = (100 / poseFps).round();

    for (Image frame in frames) {
      encoder.addFrame(frame, duration: frameDuration);
    }
    Uint8List? image = encoder.finish();

    if (image != null) {
      File(fileName).writeAsBytesSync(image);
    } else {
      throw Exception('Failed to encode GIF.');
    }
  }
}
