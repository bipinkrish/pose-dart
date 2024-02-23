// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart';
import 'package:pose/pose.dart';
import 'package:pose/numdart.dart' as nd;
import 'package:pose/numdart.dart' show MaskedArray;
import 'package:pose/src/pose_header.dart';
import 'package:tuple/tuple.dart';

class PoseVisualizer {
  Pose pose;
  int? thickness;
  late double poseFps;
  Image? background;

  PoseVisualizer(this.pose, {this.thickness}) {
    poseFps = pose.body.fps;
  }

  Image _drawFrame(MaskedArray frame, List frameConfidence, Image img) {
    Pixel pixelColor = img.getPixel(0, 0);
    Tuple3<int, int, int> backgroundColor = Tuple3<int, int, int>.fromList(
        [pixelColor.r, pixelColor.g, pixelColor.b]);

    thickness ??= (sqrt(img.width * img.height) / 150).round();
    int radius = (thickness! / 2).round();

    for (int i = 0; i < frame.data.length; i++) {
      List person = frame.data[i];
      var personConfidence = frameConfidence[i];

      List<Tuple2<int, int>> points2D = List<Tuple2<int, int>>.from(
          person.map((p) => Tuple2<int, int>(p[0], p[1])));

      int idx = 0;
      for (PoseHeaderComponent component in pose.header.components) {
        List<Tuple3<int, int, int>> colors = [
          for (var c in component.colors)
            Tuple3<int, int, int>.fromList(c) // can be reversed
        ];

        Tuple3<int, int, int> _pointColor(int pI) {
          double opacity = personConfidence[pI + idx];
          List nColor = colors[pI % component.colors.length]
              .toList()
              .map((e) => (e * opacity).toInt())
              .toList();
          List newColor = backgroundColor
              .toList()
              .map((e) => (e * (1 - opacity)).toInt())
              .toList();

          Tuple3<int, int, int> ndColor = Tuple3<int, int, int>.fromList([
            for (int i in Iterable.generate(nColor.length))
              (nColor[i] + newColor[i])
          ]);
          return ndColor;
        }

        // Draw Points
        for (int i = 0; i < component.points.length; i++) {
          if (personConfidence[i + idx] > 0) {
            Tuple2<int, int> center =
                Tuple2<int, int>.fromList(person[i + idx].take(2).toList());
            Tuple3<int, int, int> colorTuple = _pointColor(i);

            drawCircle(
              img,
              x: center.item1,
              y: center.item2,
              radius: radius,
              color: ColorFloat16.fromList([
                colorTuple.item1,
                colorTuple.item2,
                colorTuple.item3
              ].map((e) => (e.toDouble())).toList()),
            );
          }
        }

        if (pose.header.isBbox) {
          Tuple2<int, int> point1 = points2D[0 + idx];
          Tuple2<int, int> point2 = points2D[1 + idx];

          Tuple3<int, int, int> temp1 = _pointColor(0);
          Tuple3<int, int, int> temp2 = _pointColor(1);

          drawRect(img,
              x1: point1.item1,
              y1: point1.item2,
              x2: point2.item1,
              y2: point2.item2,
              color: ColorFloat16.fromList(nd.mean([
                [temp1.item1, temp1.item2, temp1.item3],
                [temp2.item1, temp2.item2, temp2.item3]
              ], axis: 0)),
              thickness: thickness!);
        } else {
          // Draw Limbs
          for (var limb in component.limbs) {
            if (personConfidence[limb.x + idx] > 0 &&
                personConfidence[limb.y + idx] > 0) {
              Tuple2<int, int> point1 = points2D[limb.x + idx];
              Tuple2<int, int> point2 = points2D[limb.y + idx];

              Tuple3<int, int, int> temp1 = _pointColor(limb.x);
              Tuple3<int, int, int> temp2 = _pointColor(limb.y);

              drawLine(img,
                  x1: point1.item1,
                  y1: point1.item2,
                  x2: point2.item1,
                  y2: point2.item2,
                  color: ColorFloat16.fromList(nd.mean([
                    [temp1.item1, temp1.item2, temp1.item3],
                    [temp2.item1, temp2.item2, temp2.item3]
                  ], axis: 0)),
                  thickness: thickness!);
            }
          }
        }

        idx += component.points.length;
      }
    }

    return img;
  }

  Iterable<Image> draw(
      {List<double> backgroundColor = const [0, 0, 0], int? maxFrames}) sync* {
    List intFrames = MaskedArray(pose.body.data, []).round();

    background = Image(
      width: pose.header.dimensions.width,
      height: pose.header.dimensions.height,
      backgroundColor: ColorFloat16.fromList(backgroundColor),
    );

    for (int i = 0;
        i < min(intFrames.length, maxFrames ?? intFrames.length);
        i++) {
      yield _drawFrame(MaskedArray(intFrames[i], []), pose.body.confidence[i],
          background!.clone());
    }
  }

  void saveGif(String fileName, {double fps = 24}) {
    Iterable<Image> frames = draw();
    int frameDuration = (100 / fps).round();

    GifEncoder encoder = GifEncoder(delay: 0, repeat: 0);
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
