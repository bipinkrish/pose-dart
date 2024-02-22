// ignore_for_file: non_constant_identifier_names

import 'package:pose/numdart.dart' show MaskedArray, ConstStructs;
import 'package:pose/numdart.dart' as nd;
import 'package:pose/src/pose_body.dart' show PoseBody;
import 'package:pose/src/pose_header.dart' show PoseHeader, PoseHeaderComponent;
import 'package:pose/utils/reader.dart';

/// Class representing a NumPoseBody, extending PoseBody.
///
/// This class is used to handle pose body data in NumPy format.
class NumPoseBody extends PoseBody {
  static final String tensorReader = 'unpack_num';

  /// Constructor for NumPoseBody.
  ///
  /// Takes [fps], [data], and [confidence] as parameters.
  NumPoseBody(double fps, MaskedArray data, List<List<dynamic>> confidence)
      : super(fps, data, confidence);

  /// Reads NumPy pose body data from a specified version.
  ///
  /// Takes [header], [reader], and [unusedKwargs] as parameters.
  /// Returns a NumPoseBody instance.
  static NumPoseBody read_v0_0(PoseHeader header, BufferReader reader,
      Map<String, dynamic> unusedKwargs) {
    double fps;
    int frames;
    List<List<dynamic>> framesD = [];
    List<List<dynamic>> framesC = [];

    // Read FPS and number of frames from the reader.
    fps = reader.unpack(ConstStructs.double_ushort);
    frames = reader.unpack(ConstStructs.ushort);

    // Calculate dimensions and points based on header components.
    int dims = header.components
            .map((c) => c.format.length)
            .reduce((value, element) => value > element ? value : element) -
        1;
    int points = header.components
        .map((c) => c.points.length)
        .reduce((value, element) => value + element);

    // Iterate over frames.
    for (int i = 0; i < frames; i++) {
      int people = reader.unpack(ConstStructs.ushort);
      List<List<dynamic>> peopleD = [];
      List<List<double>> peopleC = [];

      // Iterate over people in each frame.
      for (int pid = 0; pid < people; pid++) {
        reader.advance(ConstStructs.short);
        List<MaskedArray> personD = [];
        List<double> personC = [];

        // Iterate over components in header.
        for (PoseHeaderComponent component in header.components) {
          List<List<dynamic>> pointsList = [];
          List<dynamic> confidenceList = [];

          // Iterate over points in component.
          for (int j = 0; j < component.points.length; j++) {
            List point = reader.unpack(ConstStructs.float);
            pointsList.add(point[0]);
            confidenceList.add(point[1]);
          }

          // Create mask based on confidence.
          List<int> booleanConfidence =
              confidenceList.map((c) => c > 0 ? 0 : 1).toList();
          List<List<int>> mask = List.generate(
              component.format.length - 1, (_) => booleanConfidence);

          // Add masked array and confidence to person data.
          personD.add(MaskedArray(pointsList, mask));
          personC.addAll(confidenceList.cast<double>());
        }

        // Add person data and confidence to people lists.
        if (pid == 0) {
          peopleD.add(personD);
          peopleC.add(personC);
        }
      }

      // If no people data is available, fill with zeros.
      if (peopleD.isEmpty) {
        peopleD
            .add(List.generate(dims, (_) => List.generate(points, (_) => 0.0)));
        peopleC.add(List.generate(points, (_) => 0.0));
      }

      // Stack people data and confidence and add to frames lists.
      framesD.add(nd.stack(peopleD));
      framesC.add(nd.stack(peopleC));
    }

    // Return NumPoseBody instance.
    return NumPoseBody(fps, MaskedArray(framesD, []), framesC);
  }
}
