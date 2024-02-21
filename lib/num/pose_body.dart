// ignore_for_file: non_constant_identifier_names

import 'package:pose/numdart.dart' show MaskedArray, ConstStructs;
import 'package:pose/numdart.dart' as nd;
import 'package:pose/src/pose_body.dart' show PoseBody;
import 'package:pose/src/pose_header.dart' show PoseHeader;
import 'package:pose/utils/reader.dart';

class NumPyPoseBody extends PoseBody {
  static final String tensorReader = 'unpack_numpy';

  NumPyPoseBody(double fps, MaskedArray data, List<List<dynamic>> confidence)
      : super(fps, data, confidence);

  static NumPyPoseBody read_v0_0(PoseHeader header, BufferReader reader,
      Map<String, dynamic> unusedKwargs) {
    double fps;
    int frames;
    List<List<dynamic>> framesD = [];
    List<List<dynamic>> framesC = [];

    fps = reader.unpack(ConstStructs.double_ushort);
    frames = reader.unpack(ConstStructs.ushort);

    var dims = header.components
            .map((c) => c.format.length)
            .reduce((value, element) => value > element ? value : element) -
        1;
    var points = header.components
        .map((c) => c.points.length)
        .reduce((value, element) => value + element);

    for (var i = 0; i < frames; i++) {
      var people = reader.unpack(ConstStructs.ushort);
      List<List<dynamic>> peopleD = [];
      List<List<double>> peopleC = [];

      for (var pid = 0; pid < people; pid++) {
        reader.advance(ConstStructs.short);
        List<MaskedArray> personD = [];
        List<double> personC = [];

        for (var component in header.components) {
          List<List<dynamic>> pointsList = [];
          List<dynamic> confidenceList = [];

          for (var j = 0; j < component.points.length; j++) {
            var point = reader.unpack(ConstStructs.float);
            pointsList.add(point[0]);
            confidenceList.add(point[1]);
          }

          List<int> booleanConfidence =
              confidenceList.map((c) => c > 0 ? 0 : 1).toList();
          List<List<int>> mask = List.generate(
              component.format.length - 1, (_) => booleanConfidence);

          personD.add(MaskedArray(pointsList, mask));
          personC.addAll(confidenceList.cast<double>());
        }

        if (pid == 0) {
          peopleD.add(personD);
          peopleC.add(personC);
        }
      }

      if (peopleD.isEmpty) {
        peopleD
            .add(List.generate(dims, (_) => List.generate(points, (_) => 0.0)));
        peopleC.add(List.generate(points, (_) => 0.0));
      }

      framesD.add(nd.stack(peopleD));
      framesC.add(nd.stack(peopleC));
    }

    return NumPyPoseBody(fps, MaskedArray(framesD, []), framesC);
  }
}
